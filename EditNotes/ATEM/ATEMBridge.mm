#import "ATEMBridge.h"
#include "SDK/BMDSwitcherAPI.h"
#include <atomic>

static bool SameIID(REFIID a, REFIID b)
{
    return memcmp(&a, &b, sizeof(REFIID)) == 0;
}

static bool IsIUnknown(REFIID iid)
{
    return SameIID(iid, CFUUIDGetUUIDBytes(IUnknownUUID));
}

class SwitcherMonitor final : public IBMDSwitcherCallback
{
public:
    explicit SwitcherMonitor(void (^handler)(BMDSwitcherEventType)) : m_handler([handler copy]) {}

    HRESULT QueryInterface(REFIID iid, LPVOID *ppv) override
    {
        if (IsIUnknown(iid) || SameIID(iid, IID_IBMDSwitcherCallback)) {
            *ppv = static_cast<IBMDSwitcherCallback *>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG AddRef() override { return ++m_refCount; }
    ULONG Release() override
    {
        ULONG count = --m_refCount;
        if (count == 0)
            delete this;
        return count;
    }

    HRESULT Notify(BMDSwitcherEventType eventType, BMDSwitcherVideoMode) override
    {
        m_handler(eventType);
        return S_OK;
    }

private:
    ~SwitcherMonitor() {}
    std::atomic<ULONG> m_refCount{1};
    void (^m_handler)(BMDSwitcherEventType);
};

class RecordAVMonitor final : public IBMDSwitcherRecordAVCallback
{
public:
    explicit RecordAVMonitor(void (^handler)(BMDSwitcherRecordAVEventType)) : m_handler([handler copy]) {}

    HRESULT QueryInterface(REFIID iid, LPVOID *ppv) override
    {
        if (IsIUnknown(iid) || SameIID(iid, IID_IBMDSwitcherRecordAVCallback)) {
            *ppv = static_cast<IBMDSwitcherRecordAVCallback *>(this);
            AddRef();
            return S_OK;
        }
        *ppv = nullptr;
        return E_NOINTERFACE;
    }
    ULONG AddRef() override { return ++m_refCount; }
    ULONG Release() override
    {
        ULONG count = --m_refCount;
        if (count == 0)
            delete this;
        return count;
    }

    HRESULT Notify(BMDSwitcherRecordAVEventType eventType) override
    {
        m_handler(eventType);
        return S_OK;
    }
    HRESULT NotifyWorkingSetChange(uint32_t, BMDSwitcherRecordDiskId) override { return S_OK; }
    HRESULT NotifyDiskAvailability(BMDSwitcherRecordDiskAvailabilityEventType, BMDSwitcherRecordDiskId) override { return S_OK; }
    HRESULT NotifyStatus(BMDSwitcherRecordAVState, BMDSwitcherRecordAVError) override { return S_OK; }

private:
    ~RecordAVMonitor() {}
    std::atomic<ULONG> m_refCount{1};
    void (^m_handler)(BMDSwitcherRecordAVEventType);
};

static NSString *ConnectFailureDescription(BMDSwitcherConnectToFailure reason)
{
    switch (reason) {
        case bmdSwitcherConnectToFailureNoResponse:
            return @"No response from the switcher";
        case bmdSwitcherConnectToFailureIncompatibleFirmware:
            return @"Switcher firmware doesn't match the installed ATEM software";
        case bmdSwitcherConnectToFailureCorruptData:
            return @"Corrupt data received from the switcher";
        case bmdSwitcherConnectToFailureStateSync:
            return @"State synchronisation with the switcher failed";
        case bmdSwitcherConnectToFailureStateSyncTimedOut:
            return @"State synchronisation with the switcher timed out";
        default:
            return @"Couldn't connect to the switcher";
    }
}

/// Maps a video mode to the timecode timebase it runs at; interlaced modes count frames, not fields.
static bool TimebaseForVideoMode(BMDSwitcherVideoMode mode, NSInteger *timebase, BOOL *ntsc)
{
    switch (mode) {
        case bmdSwitcherVideoMode1080p2398:
        case bmdSwitcherVideoMode4KHDp2398:
        case bmdSwitcherVideoMode8KHDp2398:
            *timebase = 24; *ntsc = YES; return true;
        case bmdSwitcherVideoMode1080p24:
        case bmdSwitcherVideoMode4KHDp24:
        case bmdSwitcherVideoMode8KHDp24:
            *timebase = 24; *ntsc = NO; return true;
        case bmdSwitcherVideoMode625i50PAL:
        case bmdSwitcherVideoMode625i50Anamorphic:
        case bmdSwitcherVideoMode1080i50:
        case bmdSwitcherVideoMode1080p25:
        case bmdSwitcherVideoMode4KHDp25:
        case bmdSwitcherVideoMode8KHDp25:
            *timebase = 25; *ntsc = NO; return true;
        case bmdSwitcherVideoMode525i5994NTSC:
        case bmdSwitcherVideoMode525i5994Anamorphic:
        case bmdSwitcherVideoMode1080i5994:
        case bmdSwitcherVideoMode1080p2997:
        case bmdSwitcherVideoMode4KHDp2997:
        case bmdSwitcherVideoMode8KHDp2997:
            *timebase = 30; *ntsc = YES; return true;
        case bmdSwitcherVideoMode1080i60:
        case bmdSwitcherVideoMode1080p30:
        case bmdSwitcherVideoMode4KHDp30:
        case bmdSwitcherVideoMode8KHDp30:
            *timebase = 30; *ntsc = NO; return true;
        case bmdSwitcherVideoMode720p50:
        case bmdSwitcherVideoMode1080p50:
        case bmdSwitcherVideoMode4KHDp50:
        case bmdSwitcherVideoMode8KHDp50:
            *timebase = 50; *ntsc = NO; return true;
        case bmdSwitcherVideoMode720p5994:
        case bmdSwitcherVideoMode1080p5994:
        case bmdSwitcherVideoMode4KHDp5994:
        case bmdSwitcherVideoMode8KHDp5994:
            *timebase = 60; *ntsc = YES; return true;
        case bmdSwitcherVideoMode720p60:
        case bmdSwitcherVideoMode1080p60:
        case bmdSwitcherVideoMode4KHDp60:
        case bmdSwitcherVideoMode8KHDp60:
            *timebase = 60; *ntsc = NO; return true;
        default:
            return false;
    }
}

@implementation ATEMBridge {
    IBMDSwitcher *_switcher;
    IBMDSwitcherRecordAV *_recordAV;
    SwitcherMonitor *_monitor;
    RecordAVMonitor *_recordMonitor;
    NSUInteger _generation;
}

+ (BOOL)sdkInstalled
{
    IBMDSwitcherDiscovery *discovery = CreateBMDSwitcherDiscoveryInstance();
    if (discovery == nullptr)
        return NO;
    discovery->Release();
    return YES;
}

- (void)dealloc
{
    [self teardown];
}

- (void)connectToAddress:(NSString *)address
              completion:(void (^)(NSString *_Nullable, NSString *_Nullable))completion
{
    [self disconnect];
    NSUInteger generation = _generation;

    // ConnectTo blocks until the switcher answers or times out.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        IBMDSwitcherDiscovery *discovery = CreateBMDSwitcherDiscoveryInstance();
        if (discovery == nullptr) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, @"ATEM Software Control isn't installed on this Mac");
            });
            return;
        }

        IBMDSwitcher *switcher = nullptr;
        BMDSwitcherConnectToFailure reason = (BMDSwitcherConnectToFailure)0;
        HRESULT result = discovery->ConnectTo((__bridge CFStringRef)address, &switcher, &reason);
        discovery->Release();

        dispatch_async(dispatch_get_main_queue(), ^{
            if (FAILED(result) || switcher == nullptr) {
                if (generation == self->_generation)
                    completion(nil, ConnectFailureDescription(reason));
                return;
            }
            // A newer connect or disconnect superseded this attempt.
            if (generation != self->_generation) {
                switcher->Release();
                return;
            }
            [self adoptSwitcher:switcher];

            CFStringRef productName = nullptr;
            NSString *name = @"ATEM";
            if (switcher->GetProductName(&productName) == S_OK && productName != nullptr)
                name = CFBridgingRelease(productName);
            completion(name, nil);

            [self reportVideoMode];
            [self reportProjectName];
            [self requestTimecode];
        });
    });
}

- (void)adoptSwitcher:(IBMDSwitcher *)switcher
{
    _switcher = switcher;
    __weak ATEMBridge *weakSelf = self;

    _monitor = new SwitcherMonitor(^(BMDSwitcherEventType eventType) {
        NSTimeInterval uptime = NSProcessInfo.processInfo.systemUptime;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf handleSwitcherEvent:eventType uptime:uptime forSwitcher:switcher];
        });
    });
    _switcher->AddCallback(_monitor);

    // Switchers without built-in recording don't expose this interface.
    if (_switcher->QueryInterface(IID_IBMDSwitcherRecordAV, (void **)&_recordAV) == S_OK && _recordAV != nullptr) {
        _recordMonitor = new RecordAVMonitor(^(BMDSwitcherRecordAVEventType eventType) {
            if (eventType != bmdSwitcherRecordAVEventTypeFilenameChanged)
                return;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf reportProjectName];
            });
        });
        _recordAV->AddCallback(_recordMonitor);
    } else {
        _recordAV = nullptr;
    }
}

- (void)teardown
{
    if (_recordAV != nullptr) {
        if (_recordMonitor != nullptr)
            _recordAV->RemoveCallback(_recordMonitor);
        _recordAV->Release();
        _recordAV = nullptr;
    }
    if (_recordMonitor != nullptr) {
        _recordMonitor->Release();
        _recordMonitor = nullptr;
    }
    if (_switcher != nullptr) {
        if (_monitor != nullptr)
            _switcher->RemoveCallback(_monitor);
        _switcher->Release();
        _switcher = nullptr;
    }
    if (_monitor != nullptr) {
        _monitor->Release();
        _monitor = nullptr;
    }
}

- (void)disconnect
{
    _generation++;
    [self teardown];
}

- (void)requestTimecode
{
    if (_switcher != nullptr)
        _switcher->RequestTimeCode();
}

- (void)handleSwitcherEvent:(BMDSwitcherEventType)eventType
                     uptime:(NSTimeInterval)uptime
                forSwitcher:(IBMDSwitcher *)switcher
{
    // Ignore events queued by a switcher we've since let go of.
    if (_switcher == nullptr || _switcher != switcher)
        return;

    switch (eventType) {
        case bmdSwitcherEventTypeDisconnected:
            [self disconnect];
            [self.delegate atemBridgeDidDisconnect];
            break;
        case bmdSwitcherEventTypeTimeCodeChanged: {
            uint8_t hours = 0, minutes = 0, seconds = 0, frames = 0;
            bool dropFrame = false;
            if (_switcher->GetTimeCode(&hours, &minutes, &seconds, &frames, &dropFrame) == S_OK) {
                [self.delegate atemBridgeDidReceiveTimecodeWithHours:hours
                                                             minutes:minutes
                                                             seconds:seconds
                                                              frames:frames
                                                           dropFrame:dropFrame
                                                              uptime:uptime];
            }
            break;
        }
        case bmdSwitcherEventTypeVideoModeChanged:
            [self reportVideoMode];
            break;
        default:
            break;
    }
}

- (void)reportVideoMode
{
    BMDSwitcherVideoMode mode;
    NSInteger timebase = 0;
    BOOL ntsc = NO;
    if (_switcher != nullptr && _switcher->GetVideoMode(&mode) == S_OK && TimebaseForVideoMode(mode, &timebase, &ntsc))
        [self.delegate atemBridgeVideoModeDidChangeWithTimebase:timebase ntsc:ntsc];
}

- (void)reportProjectName
{
    if (_switcher == nullptr)
        return;
    NSString *name = nil;
    CFStringRef filename = nullptr;
    if (_recordAV != nullptr && _recordAV->GetFilename(&filename) == S_OK && filename != nullptr)
        name = CFBridgingRelease(filename);
    [self.delegate atemBridgeProjectNameDidChange:name.length > 0 ? name : nil];
}

@end
