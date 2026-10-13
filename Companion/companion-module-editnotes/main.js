const { InstanceBase, InstanceStatus, Regex, combineRgb, runEntrypoint } = require('@companion-module/base')

const POLL_INTERVAL_MS = 2000
const BLACK = combineRgb(0, 0, 0)
const WHITE = combineRgb(255, 255, 255)

class EditNotesInstance extends InstanceBase {
	async init(config) {
		this.config = config
		this.shortcuts = []
		this.oscPort = 0
		this.lastState = ''
		this.refreshDefinitions()
		this.startPolling()
	}

	async destroy() {
		clearInterval(this.pollTimer)
	}

	async configUpdated(config) {
		this.config = config
		this.lastState = ''
		this.startPolling()
	}

	getConfigFields() {
		return [
			{
				type: 'static-text',
				id: 'info',
				width: 12,
				label: 'Information',
				value:
					'Buttons for your EditNotes shortcuts appear under Presets and stay in sync with the app. ' +
					'The port is the "Module port" shown in EditNotes > Settings > OSC.',
			},
			{ type: 'textinput', id: 'host', label: 'EditNotes IP', width: 8, default: '127.0.0.1', regex: Regex.IP },
			{ type: 'textinput', id: 'port', label: 'Module port', width: 4, default: '9301', regex: Regex.PORT },
		]
	}

	startPolling() {
		clearInterval(this.pollTimer)
		if (!this.config.host) {
			this.updateStatus(InstanceStatus.BadConfig, 'Set the EditNotes IP')
			return
		}
		this.updateStatus(InstanceStatus.Connecting)
		this.poll()
		this.pollTimer = setInterval(() => this.poll(), POLL_INTERVAL_MS)
	}

	/** Fetches the shortcut list from EditNotes and rebuilds buttons when it has changed. */
	async poll() {
		const url = `http://${this.config.host}:${Number(this.config.port) || 9301}/api/state`
		let text
		try {
			const response = await fetch(url, { signal: AbortSignal.timeout(1500) })
			if (!response.ok) throw new Error(`HTTP ${response.status}`)
			text = await response.text()
		} catch (error) {
			this.lastState = ''
			this.updateStatus(InstanceStatus.ConnectionFailure, `EditNotes isn't answering on ${url}`)
			return
		}
		if (text === this.lastState) return

		let state
		try {
			state = JSON.parse(text)
		} catch (error) {
			this.updateStatus(InstanceStatus.UnknownError, 'Unexpected reply from EditNotes')
			return
		}
		this.lastState = text
		this.shortcuts = Array.isArray(state.shortcuts) ? state.shortcuts : []
		this.oscPort = Number(state.oscPort) || 0
		this.projectName = state.projectName || ''
		this.refreshDefinitions()
		this.checkFeedbacks('shortcut_color')
		if (this.oscPort) {
			this.updateStatus(InstanceStatus.Ok)
		} else {
			this.updateStatus(InstanceStatus.UnknownWarning, 'Turn on "Receive OSC" in EditNotes to trigger markers')
		}
	}

	refreshDefinitions() {
		this.setActionDefinitions(this.actions())
		this.setFeedbackDefinitions(this.feedbacks())
		this.setPresetDefinitions(this.presets())
		this.setVariableDefinitions([
			{ variableId: 'project_name', name: 'Project name' },
			...this.shortcuts.map((s) => ({ variableId: labelVariable(s.id), name: `Label of shortcut ${s.index}` })),
		])
		const values = { project_name: this.projectName || '' }
		for (const s of this.shortcuts) values[labelVariable(s.id)] = s.label
		this.setVariableValues(values)
	}

	send(path, args = []) {
		if (!this.config.host || !this.oscPort) {
			this.log('warn', 'Not sent: EditNotes is unreachable or has OSC turned off')
			return
		}
		this.oscSend(this.config.host, this.oscPort, path, args)
	}

	shortcutChoices() {
		return this.shortcuts.map((s) => ({ id: s.id, label: `${s.index}. ${s.label}` }))
	}

	actions() {
		const choices = this.shortcutChoices()
		return {
			shortcut: {
				name: 'Add shortcut marker',
				options: [
					{
						type: 'dropdown',
						id: 'shortcut',
						label: 'Shortcut',
						choices,
						default: choices[0]?.id ?? '',
						// A typed label or list position also works, e.g. "GFX" or "2".
						allowCustom: true,
					},
				],
				callback: async (action) => {
					const shortcut = String(action.options.shortcut ?? '').trim()
					if (shortcut) this.send('/editnotes/shortcut', [{ type: 's', value: shortcut }])
				},
			},
			note: {
				name: 'Add note',
				options: [
					{ type: 'textinput', id: 'text', label: 'Note', default: '', useVariables: true },
					{ type: 'textinput', id: 'name', label: 'Marker name (optional)', default: '', useVariables: true },
					{
						type: 'dropdown',
						id: 'color',
						label: 'Colour',
						default: 'blue',
						choices: ['green', 'red', 'purple', 'orange', 'yellow', 'white', 'blue', 'cyan'].map((id) => ({
							id,
							label: id[0].toUpperCase() + id.slice(1),
						})),
					},
				],
				callback: async (action, context) => {
					const text = await context.parseVariablesInString(action.options.text)
					const name = await context.parseVariablesInString(action.options.name)
					if (!text.trim()) return
					this.send('/editnotes/note', [
						{ type: 's', value: text },
						{ type: 's', value: name },
						{ type: 's', value: action.options.color },
					])
				},
			},
			undo: {
				name: 'Remove last marker',
				options: [],
				callback: async () => this.send('/editnotes/undo'),
			},
		}
	}

	feedbacks() {
		return {
			// Keeps a button's colours matched to its shortcut when the colour is changed in EditNotes.
			shortcut_color: {
				type: 'advanced',
				name: 'Use shortcut colour',
				options: [
					{
						type: 'dropdown',
						id: 'shortcut',
						label: 'Shortcut',
						choices: this.shortcutChoices(),
						default: this.shortcutChoices()[0]?.id ?? '',
					},
				],
				callback: (feedback) => {
					const shortcut = this.shortcuts.find((s) => s.id === feedback.options.shortcut)
					return shortcut ? buttonColors(shortcut) : {}
				},
			},
		}
	}

	/** One ready-made button per EditNotes shortcut, plus an undo button. */
	presets() {
		const presets = {}
		for (const shortcut of this.shortcuts) {
			presets[`shortcut_${shortcut.id}`] = {
				type: 'button',
				category: 'Shortcuts',
				name: shortcut.label,
				style: {
					// The label is a variable so renaming the shortcut in EditNotes renames the button.
					text: `$(${this.label}:${labelVariable(shortcut.id)})`,
					size: '18',
					...buttonColors(shortcut),
				},
				steps: [{ down: [{ actionId: 'shortcut', options: { shortcut: shortcut.id } }], up: [] }],
				feedbacks: [{ feedbackId: 'shortcut_color', options: { shortcut: shortcut.id } }],
			}
		}
		presets.undo = {
			type: 'button',
			category: 'Shortcuts',
			name: 'Remove last marker',
			style: { text: 'UNDO\\nMARKER', size: '14', color: WHITE, bgcolor: combineRgb(60, 60, 60) },
			steps: [{ down: [{ actionId: 'undo', options: {} }], up: [] }],
			feedbacks: [],
		}
		return presets
	}
}

function labelVariable(id) {
	return `label_${String(id).replace(/[^A-Za-z0-9]/g, '_')}`
}

function buttonColors(shortcut) {
	const [r, g, b] = shortcut.rgb ?? [60, 60, 60]
	// Dark text on the light colours (yellow, white), white on the rest.
	const luminance = 0.299 * r + 0.587 * g + 0.114 * b
	return { bgcolor: combineRgb(r, g, b), color: luminance > 170 ? BLACK : WHITE }
}

runEntrypoint(EditNotesInstance, [])
