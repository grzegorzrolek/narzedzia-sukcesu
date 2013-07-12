# Makefile for Narzędzia Sukcesu the logotype font
# Copyright 2013 Grzegorz Rolek


TARGET = build/NarzedziaSukcesu.ttf

# Null.ttf submodule will be cloned automatically if it hasn't been cloned by hand already.
NULLDIR = null-ttf
NULL = $(NULLDIR)/Null.ttf

# Helper files to make some methodology in fusing the individual tables possible.
BASICS = $(addprefix .,head name maxp post glyf cmap hmtx hhea)
HINTS = .hints
MORPHING = .morx
KERNING = .kern
OTLAYOUT = .otlayout

# First the basics (note the table order), hints, and the smarts (without particular order).
all: $(BASICS) $(HINTS) $(MORPHING) $(KERNING) $(OTLAYOUT)

$(OTLAYOUT): features.fea $(NULL) | $(TARGET)
	makeotf -f $(TARGET) -o $(basename $(TARGET)).otf -ff features.fea
	mv $(basename $(TARGET)).otf $(TARGET)
	ftxdumperfuser -k -t 'OS/2' $(TARGET)
	for TABLE in head name post cmap hhea; do ftxdumperfuser -d $$TABLE.xml -t $$TABLE $(TARGET); done
	@touch $@

$(KERNING): kerning.kif post.xml $(NULL) | $(TARGET)
	sh kiftohex.sh -p post.xml $< >kern.xml
	ftxdumperfuser -d kern.xml -g -t kern $(TARGET)
	@touch $@

$(MORPHING): morphing.mif $(NULL) | $(TARGET)
	ftxenhancer -m $< $(TARGET)
	@touch $@

$(HINTS): .glyf $(NULL) | $(TARGET)
	ttfautohint -f -n -c $(TARGET) $(basename $(TARGET))_hinted.ttf
	mv $(basename $(TARGET))_hinted.ttf $(TARGET)
	@touch $@

$(BASICS): .%: %.xml $(NULL) | $(TARGET) 
	ftxdumperfuser -d $< -t $(basename $<) $(TARGET)
	@touch $@

$(TARGET): $(NULL) | build
	cp $< $@

$(NULL): FORCE
ifeq ($(wildcard $(NULL)),)
	git submodule update --init $(NULLDIR)
endif
	@cd $(NULLDIR) && make

FORCE:

build:
	mkdir $@

test:
	@ftxvalidator -T -o test.out $(TARGET)

list:
	@ftxdumperfuser -l $(TARGET)

cleanall: clean
	@rm -rf build

clean:
	@rm -rf $(BASICS) $(HINTS) $(MORPHING) $(KERNING) $(OTLAYOUT) kern.xml build/current.fpr test.out
