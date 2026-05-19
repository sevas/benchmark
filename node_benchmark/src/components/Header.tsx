import { Bell, Search, Settings } from 'lucide-react'
import * as DropdownMenu from '@radix-ui/react-dropdown-menu'
import { cn } from '../lib/utils'
import { useAppStore } from '../store'

export default function Header() {
  const count = useAppStore((s) => s.count)
  const increment = useAppStore((s) => s.increment)

  return (
    <header
      className={cn('flex items-center gap-4 p-4 border-b')}
      style={{ display: 'flex', alignItems: 'center', gap: '1rem', padding: '1rem' }}
    >
      <Search size={20} aria-label="Search" />
      <Bell size={20} aria-label="Notifications" />
      <span>Alerts: {count}</span>

      <DropdownMenu.Root>
        <DropdownMenu.Trigger asChild>
          <button type="button" aria-label="Settings">
            <Settings size={20} />
          </button>
        </DropdownMenu.Trigger>
        <DropdownMenu.Portal>
          <DropdownMenu.Content sideOffset={4}>
            <DropdownMenu.Item onSelect={increment}>
              Increment counter
            </DropdownMenu.Item>
            <DropdownMenu.Separator />
            <DropdownMenu.Item onSelect={() => console.log('settings')}>
              Open settings
            </DropdownMenu.Item>
          </DropdownMenu.Content>
        </DropdownMenu.Portal>
      </DropdownMenu.Root>
    </header>
  )
}
