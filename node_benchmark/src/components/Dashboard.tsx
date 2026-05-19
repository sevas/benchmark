import { useQuery } from '@tanstack/react-query'
import { motion } from 'framer-motion'
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  ResponsiveContainer,
} from 'recharts'
import { format, subDays } from 'date-fns'
import { range } from 'lodash'
import { fetchChartData, type DataPoint } from '../lib/api'
import { useAppStore } from '../store'

const seedData: DataPoint[] = range(14).map((i) => ({
  date: format(subDays(new Date(), 13 - i), 'MMM dd'),
  value: Math.round(20 + Math.random() * 80),
}))

export default function Dashboard() {
  const addItem = useAppStore((s) => s.addItem)

  const { data, isLoading, isError } = useQuery<DataPoint[]>({
    queryKey: ['chartData'],
    queryFn: fetchChartData,
    enabled: false, // don't fire real requests in benchmark / tests
    initialData: seedData,
  })

  const handleClick = () => addItem(`item-${Date.now()}`)

  return (
    <motion.main
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3 }}
      style={{ padding: '2rem' }}
    >
      <h1>Dashboard</h1>
      {isLoading && <p>Loading…</p>}
      {isError && <p>Failed to load data.</p>}

      <ResponsiveContainer width="100%" height={300}>
        <LineChart data={data}>
          <CartesianGrid strokeDasharray="3 3" />
          <XAxis dataKey="date" />
          <YAxis />
          <Tooltip />
          <Line type="monotone" dataKey="value" stroke="#6366f1" dot={false} />
        </LineChart>
      </ResponsiveContainer>

      <button type="button" onClick={handleClick} style={{ marginTop: '1rem' }}>
        Add item
      </button>
    </motion.main>
  )
}
