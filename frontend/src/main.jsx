import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { Provider } from 'react-redux'
import { HashRouter } from 'react-router-dom'
import App from './App.jsx'
import { ANT_THEME, AntApp, ConfigProvider } from './assets/antd'
import store from './redux/store'
import './style.css'

// HashRouter: links look like /#/dashboard and /#/user/<id>, so the built portal works from any
// static host (or the backend) without server-side route rewrites.
// ConfigProvider + AntApp: the Ant Design theme and the message API the toast uses.
createRoot(document.getElementById('root')).render(
  <StrictMode>
    <Provider store={store}>
      <ConfigProvider theme={ANT_THEME}>
        <AntApp>
          <HashRouter>
            <App />
          </HashRouter>
        </AntApp>
      </ConfigProvider>
    </Provider>
  </StrictMode>,
)
