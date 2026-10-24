import 'vuetify/styles'
import { createVuetify } from 'vuetify'

export default createVuetify({
  theme: {
    defaultTheme: 'vwebLight',
    themes: {
      vwebLight: {
        colors: {
          primary: '#1769aa',
          secondary: '#52606d',
          surface: '#ffffff',
          background: '#f3f6fa',
        },
      },
    },
  },
})
