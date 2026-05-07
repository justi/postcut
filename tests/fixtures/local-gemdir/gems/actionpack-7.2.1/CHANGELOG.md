## Rails 7.2.1 ##

*   Add link-local IP ranges to `ActionDispatch::RemoteIp` default proxies.

*   Allow methods starting with underscore to be action methods.


## Rails 7.2.0 ##

*   Submit test requests using `as: :html` with `Content-Type: x-www-form-urlencoded`.

*   `remote_ip` no longer ignores IPs in X-Forwarded-For headers if they are private.
