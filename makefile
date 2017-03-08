.PHONY: all images

all: images

images: $(patsubst %.uxf,%.png, $(shell find -type f -name '*.uxf'))

%.png: %.uxf
	umlet -action=convert -format=png "-filename=$<" "-output=$@"
