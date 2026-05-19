import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import * as Dialog from '@radix-ui/react-dialog'

const schema = z.object({
  name: z.string().min(1, 'Name is required'),
  email: z.string().email('Invalid email address'),
  message: z.string().min(10, 'Message must be at least 10 characters'),
})

type FormData = z.infer<typeof schema>

export default function ContactForm() {
  const {
    register,
    handleSubmit,
    reset,
    formState: { errors, isSubmitSuccessful },
  } = useForm<FormData>({ resolver: zodResolver(schema) })

  const onSubmit = (data: FormData) => {
    console.log('Submitted:', data)
    reset()
  }

  return (
    <Dialog.Root>
      <Dialog.Trigger asChild>
        <button type="button" style={{ margin: '2rem' }}>
          Open contact form
        </button>
      </Dialog.Trigger>

      <Dialog.Portal>
        <Dialog.Overlay style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,.4)' }} />
        <Dialog.Content
          style={{
            position: 'fixed',
            top: '50%',
            left: '50%',
            transform: 'translate(-50%,-50%)',
            background: '#fff',
            padding: '2rem',
            borderRadius: '8px',
            width: '400px',
          }}
        >
          <Dialog.Title>Contact Us</Dialog.Title>
          <Dialog.Description>Fill in the form below.</Dialog.Description>

          {isSubmitSuccessful && <p style={{ color: 'green' }}>Sent!</p>}

          <form onSubmit={handleSubmit(onSubmit)} style={{ display: 'flex', flexDirection: 'column', gap: '0.75rem' }}>
            <div>
              <input {...register('name')} placeholder="Name" style={{ width: '100%' }} />
              {errors.name && <span style={{ color: 'red', fontSize: '0.8rem' }}>{errors.name.message}</span>}
            </div>
            <div>
              <input {...register('email')} placeholder="Email" style={{ width: '100%' }} />
              {errors.email && <span style={{ color: 'red', fontSize: '0.8rem' }}>{errors.email.message}</span>}
            </div>
            <div>
              <textarea {...register('message')} placeholder="Message" rows={4} style={{ width: '100%' }} />
              {errors.message && <span style={{ color: 'red', fontSize: '0.8rem' }}>{errors.message.message}</span>}
            </div>
            <button type="submit">Submit</button>
          </form>

          <Dialog.Close asChild>
            <button type="button" style={{ marginTop: '1rem' }}>Cancel</button>
          </Dialog.Close>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}
