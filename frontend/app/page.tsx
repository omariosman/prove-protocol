import { Header } from '@/components/Header'
import { CreateTaskForm } from '@/components/CreateTaskForm'
import { TaskFeed } from '@/components/TaskFeed'
import { AgentProfile } from '@/components/AgentProfile'
import { Footer } from '@/components/Footer'

export default function Home() {
	return (
		<main className="min-h-screen">
			<Header />
			<div className="mx-auto flex max-w-4xl flex-col gap-6 px-6 py-8">
				<CreateTaskForm />
				<TaskFeed />
				<AgentProfile />
			</div>
			<Footer />
		</main>
	)
}
