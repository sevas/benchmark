import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter, Routes, Route } from 'react-router-dom'
import Header from './components/Header'
import Dashboard from './components/Dashboard'
import ContactForm from './components/ContactForm'

const queryClient = new QueryClient()

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <Header />
        <Routes>
          <Route path="/" element={<Dashboard />} />
          <Route path="/contact" element={<ContactForm />} />
        </Routes>
      </BrowserRouter>
    </QueryClientProvider>
  )
}

export default App
