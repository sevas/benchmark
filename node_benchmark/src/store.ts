import { create } from 'zustand'

interface AppState {
  count: number
  items: string[]
  increment: () => void
  addItem: (item: string) => void
}

export const useAppStore = create<AppState>()((set) => ({
  count: 0,
  items: [],
  increment: () => set((state) => ({ count: state.count + 1 })),
  addItem: (item: string) =>
    set((state) => ({ items: [...state.items, item] })),
}))
