---
layout: post
title:  "Spinning a Laser Printer Polygon Mirror"
date:   2021-01-01 +0100
categories: [pcb]
---

I want to play around with [laser direct imaging](https://www.pcbgogo.com/Blog/Explaining_Laser_Direct_Imaging_in_PCB_Fabrication_by_PCBGOGO.html), so I bought an old laser printer for it's spinning polygon mirror. This blog post is how I got it spinning.

![Overview]({{ site.baseurl }}/diagrams/spinning-polygon-mirror/overview.jpg)

First I checked the controller chip: AN44002A. Unfortunately I could not find a datasheet. The best I got was the following picture:

![Ali Express]({{ site.baseurl }}/diagrams/spinning-polygon-mirror/imageAliExpress.jpg)

Using the google translate app on my phone I got (from left to right): "2khz pulse width speed regulation", "power supply negative electrode" and "power supply positive electrode". I soldered three cables to the vias close to the connector and applyed 24V. Turned out the motor driver switches on for about 2ms after each falling edge on the PWM pin. This got the mirror spinning, but it was loud and pretty fast.

So I decided to roll my own motor driver. Poking around with my oscilloscope I found that the three connections you see the wires soldered on in the photos connect to the motor coils. I cut the connection on the PCB and connected the three wires:

![Close Up]({{ site.baseurl }}/diagrams/spinning-polygon-mirror/cutHighlight.jpg)

Then I built the following circuit on a breadboard:

![Schematic]({{ site.baseurl }}/diagrams/spinning-polygon-mirror/schematic.svg)


![Breadboard]({{ site.baseurl }}/diagrams/spinning-polygon-mirror/breadboard1.jpg)

On the arduino I used timer 2 to generate a PWM signal at 62.5 kHz toggling the enable input of the L293D. And the following step list is used to drive the coils:

````
uint8_t steps[] = {0b110, 0b100, 0b101, 0b001, 0b011, 0b010};
````

The following video shows the mirror in action:

<iframe id="ytplayer" type="text/html" width="640" height="360"
  src="https://www.youtube.com/embed/l2KBbxyOg50"
  frameborder="0"></iframe>