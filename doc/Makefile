TOP=hazard3

.PHONY: all clean view spell

all: spell $(TOP).pdf

view: all
	xdg-open $(TOP).pdf

clean:
	rm -f $(TOP).pdf

spell:
ifeq (,$(shell which codespell))
	@echo "Install codespell to check spelling"
else
	@find -name "*.adoc" | xargs codespell -L hart
	@echo "No spelling errors found"
endif

$(TOP).pdf: $(shell find -name "*.adoc" | grep -v rev.adoc)
	@echo ":revdate: Updated: `date +%Y-%b-%d`" > rev.adoc
	asciidoctor-pdf $(TOP).adoc
