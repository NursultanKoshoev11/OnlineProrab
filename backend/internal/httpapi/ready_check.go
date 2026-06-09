package httpapi

var readyCheck = func() bool { return true }

func SetReadyCheck(fn func() bool) {
	if fn == nil {
		readyCheck = func() bool { return true }
		return
	}
	readyCheck = fn
}
