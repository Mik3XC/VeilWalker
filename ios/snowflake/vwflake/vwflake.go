// Package vwflake wraps the Tor Project's Snowflake proxy for VeilWalker's Wake Mode, built for iOS with gomobile.
//
// It exposes start, stop and one number: traffic relayed. Snowflake's events also carry a client country and
// connection counts; this wrapper drops them, so nothing about who was helped ever reaches the app.
package vwflake

import (
	"sync"
	"time"

	"gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake/v2/common/event"
	sf "gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake/v2/proxy/lib"
)

// Traffic receives bytes relayed (in + out) every few seconds while the proxy runs. Implemented in Swift.
type Traffic interface {
	Relayed(bytes int64)
}

var (
	mu      sync.Mutex
	proxy   *sf.SnowflakeProxy
	lastErr string
)

type listener struct{ t Traffic }

func (l listener) OnNewSnowflakeEvent(e event.SnowflakeEvent) {
	// Only the periodic byte totals; everything else (countries, connection events) is ignored on purpose.
	if s, ok := e.(event.EventOnProxyStats); ok && l.t != nil {
		// Snowflake reports these in KB (bytes / 1000).
		if n := (s.InboundBytes + s.OutboundBytes) * 1000; n > 0 {
			l.t.Relayed(n)
		}
	}
}

// Start runs a standalone snowflake with the Tor Project's default broker, relay and STUN servers, serving up to
// `capacity` people at once. Returns at once; the proxy runs until Stop.
func Start(capacity int, t Traffic) {
	mu.Lock()
	defer mu.Unlock()
	if proxy != nil {
		return
	}
	d := event.NewSnowflakeEventDispatcher()
	d.AddSnowflakeEventListener(listener{t})
	p := &sf.SnowflakeProxy{
		Capacity:        uint(capacity),
		EventDispatcher: d,
		SummaryInterval: 5 * time.Second,
		ProxyType:       "iptproxy", // the mobile-app proxy type the broker already knows
		// Same as the official proxy's default: only ever forward to the Tor Project's own Snowflake relays.
		RelayDomainNamePattern: "snowflake.torproject.net$",
	}
	proxy = p
	lastErr = ""
	go func() {
		if err := p.Start(); err != nil {
			mu.Lock()
			lastErr = err.Error()
			if proxy == p {
				proxy = nil
			}
			mu.Unlock()
		}
	}()
}

// Stop closes every connection and shuts the snowflake down.
func Stop() {
	mu.Lock()
	p := proxy
	proxy = nil
	mu.Unlock()
	if p != nil {
		p.Stop()
	}
}

// Running reports whether a snowflake is up.
func Running() bool {
	mu.Lock()
	defer mu.Unlock()
	return proxy != nil
}

// LastError is the reason the last Start failed, or "".
func LastError() string {
	mu.Lock()
	defer mu.Unlock()
	return lastErr
}
