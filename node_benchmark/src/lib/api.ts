import axios from 'axios'

export const apiClient = axios.create({
  baseURL: '/api',
  timeout: 5000,
})

export interface DataPoint {
  date: string
  value: number
}

export const fetchChartData = (): Promise<DataPoint[]> =>
  apiClient.get<DataPoint[]>('/chart').then((r) => r.data)
