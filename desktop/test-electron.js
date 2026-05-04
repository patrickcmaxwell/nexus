const e = require('electron')
console.log('type:', typeof e)
console.log('keys:', Object.keys(e).slice(0, 10))
const {app, BrowserWindow} = e
console.log('app:', typeof app)
setTimeout(() => process.exit(0), 1000)
