import type { StoryObj } from '@storybook/vue3-vite'
import { ref } from 'vue'

import ButtonStyled from '../../components/base/ButtonStyled.vue'
import ShareModal from '../../components/modal/ShareModal.vue'

const meta = {
	title: 'Modal/ShareModal',
	component: ShareModal,
}

export default meta
type Story = StoryObj<typeof ShareModal>

export const LinkShare: Story = {
	args: {
		header: 'Share link',
		shareTitle: 'Bbsmc',
		shareText: 'Check this out on Bbsmc',
		link: true,
	},
	render: (args) => ({
		components: { ShareModal, ButtonStyled },
		setup() {
			const modalRef = ref<InstanceType<typeof ShareModal> | null>(null)
			const openModal = () => {
				modalRef.value?.show('https://bbsmc.org.cn')
			}
			return { args, modalRef, openModal }
		},
		template: `
			<div>
				<ButtonStyled color="brand">
					<button @click="openModal">Open Link Share Modal</button>
				</ButtonStyled>
				<ShareModal ref="modalRef" v-bind="args" />
			</div>
		`,
	}),
}

export const TextShare: Story = {
	args: {
		header: 'Share text',
		shareTitle: 'Bbsmc',
		shareText: 'Invite your friends to try Bbsmc.',
		link: false,
	},
	render: (args) => ({
		components: { ShareModal, ButtonStyled },
		setup() {
			const modalRef = ref<InstanceType<typeof ShareModal> | null>(null)
			const openModal = () => {
				modalRef.value?.show('https://bbsmc.org.cn')
			}
			return { args, modalRef, openModal }
		},
		template: `
			<div>
				<ButtonStyled color="brand">
					<button @click="openModal">Open Text Share Modal</button>
				</ButtonStyled>
				<ShareModal ref="modalRef" v-bind="args" />
			</div>
		`,
	}),
}
