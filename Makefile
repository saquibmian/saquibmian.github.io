.PHONY: default serve

default: serve

serve:
	hugo server --ignoreCache --noHTTPCache

