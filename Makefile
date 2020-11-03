SHELL=/bin/bash

.PHONY: ci clean local remote

local: index.bs
	bikeshed --die-on=warning spec index.bs index.html

remote: index.html

ci: index.bs index.html
	mkdir -p out
	cp index.html out/

clean:
	rm index.html

index.html: index.bs
	@ (HTTP_STATUS=$$(curl https://api.csswg.org/bikeshed/ \
	                       --output index.html \
	                       --write-out "%{http_code}" \
	                       --header "Accept: text/plain, text/html" \
												 -F die-on=warning \
	                       -F file=@index.bs) && \
	[[ "$$HTTP_STATUS" -eq "200" ]]) || ( \
		echo ""; cat index.html; echo ""; \
		rm -f index.html; \
		exit 22 \
	);
