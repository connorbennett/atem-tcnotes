const { InstanceBase, InstanceStatus, Regex, combineRgb, runEntrypoint } = require('@companion-module/base')

const COLORS = {
	green: combineRgb(76, 176, 80),
	red: combineRgb(224, 64, 64),
	purple: combineRgb(155, 89, 208),
	orange: combineRgb(240, 138, 36),
	yellow: combineRgb(232, 206, 46),
	white: combineRgb(230, 230, 230),
	blue: combineRgb(61, 125, 240),
	cyan: combineRgb(46, 196, 214),
}

// Mirrors the shortcuts EditNotes ships with; edit the button's action to match your own.
const DEFAULT_SHORTCUTS = [
	['GFX', 'cyan'],
	['VFX', 'purple'],
	['TAKE', 'green'],
	['MUSIC', 'orange'],
	['AUDIO', 'yellow'],
	['CHECK', 'red'],
]

class EditNotesInstance extends InstanceBase {
	async init(config) {
		this.config = config
		this.setActionDefinitions(this.actions())
		this.setPresetDefinitions(this.presets())
		this.updateStatus(config.host ? InstanceStatus.Ok : InstanceStatus.BadConfig)
	}

	async destroy() {}

	async configUpdated(config) {
		this.config = config
		this.updateStatus(config.host ? InstanceStatus.Ok : InstanceStatus.BadConfig)
	}

	getConfigFields() {
		return [
			{ type: 'textinput', id: 'host', label: 'Target IP', width: 8, default: '127.0.0.1', regex: Regex.IP },
			{ type: 'textinput', id: 'port', label: 'Port', width: 4, default: '9300', regex: Regex.PORT },
		]
	}

	send(path, args = []) {
		if (!this.config.host) return
		this.oscSend(this.config.host, Number(this.config.port) || 9300, path, args)
	}

	actions() {
		return {
			shortcut: {
				name: 'Trigger shortcut',
				options: [
					{
						type: 'textinput',
						id: 'shortcut',
						label: 'Shortcut label or number',
						default: 'GFX',
						useVariables: true,
					},
				],
				callback: async (action, context) => {
					const shortcut = (await context.parseVariablesInString(action.options.shortcut)).trim()
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
						choices: Object.keys(COLORS).map((id) => ({ id, label: id[0].toUpperCase() + id.slice(1) })),
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

	presets() {
		const presets = {}
		for (const [label, color] of DEFAULT_SHORTCUTS) {
			presets[`shortcut_${label}`] = {
				type: 'button',
				category: 'Shortcuts',
				name: label,
				style: {
					text: label,
					size: '18',
					color: color === 'yellow' ? combineRgb(0, 0, 0) : combineRgb(255, 255, 255),
					bgcolor: COLORS[color],
				},
				steps: [{ down: [{ actionId: 'shortcut', options: { shortcut: label } }], up: [] }],
				feedbacks: [],
			}
		}
		presets.undo = {
			type: 'button',
			category: 'Shortcuts',
			name: 'Remove last marker',
			style: { text: 'UNDO\\nMARKER', size: '14', color: combineRgb(255, 255, 255), bgcolor: combineRgb(60, 60, 60) },
			steps: [{ down: [{ actionId: 'undo', options: {} }], up: [] }],
			feedbacks: [],
		}
		return presets
	}
}

runEntrypoint(EditNotesInstance, [])
