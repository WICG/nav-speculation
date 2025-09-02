SHELL=/bin/bash

bikeshed_files = prefetch.bs prerendering.bs
html_files = index.html no-vary-search.html speculation-rules.html

.PHONY: ci clean local remote

local: $(bikeshed_files)
	$(foreach source,$(bikeshed_files),bikeshed --die-on=warning spec $(source) $(source:.bs=.html);)

remote: $(bikeshed_files:.bs=.html)

ci: $(html_files) $(bikeshed_files:.bs=.html)
	mkdir -p out
	cp $^ out/

clean:
	rm -f $(bikeshed_files:.bs=.html)

%.html: %.bs
	@ (HTTP_STATUS=$$(curl https://api.csswg.org/bikeshed/ \
	                       --output $@ \
	                       --write-out "%{http_code}" \
	                       --header "Accept: text/plain, text/html" \
												 -F die-on=warning \
	                       -F file=@$<) && \
	[[ "$$HTTP_STATUS" -eq "200" ]]) || ( \
		echo ""; cat $@; echo ""; \
		rm -f $@; \
		exit 22 \
	);
