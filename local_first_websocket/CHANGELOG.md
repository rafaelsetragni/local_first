## 0.2.0

* Fixed authentication flow in test suite
* Improved test reliability by properly simulating server auth_success responses
* Enhanced test coverage for connection and reconnection scenarios
* Updated call count expectations to match actual authentication behavior
* All 123 tests now passing with improved stability

## 0.1.0

* Initial release
* WebSocket-based real-time synchronization strategy
* Bidirectional sync (push and pull)
* Automatic reconnection on connection loss
* Heartbeat/ping-pong for connection health monitoring
* Queue for pending events during disconnection
* Example app with WebSocket server implementation
* Dynamic authentication credential updates:
  * `updateAuthToken()` - Update authentication token
  * `updateHeaders()` - Update custom headers
  * `updateCredentials()` - Update both token and headers
* Automatic re-authentication when credentials are updated during active connection
* Read-only getters for `authToken` and `headers`
* Removed all force unwrap operators (!) for safer null handling
