# Version 1.0
FROM ubuntu:14.04
MAINTAINER Florian GAUVIN "florian.gauvin@nl.thalesgroup.com"

ENV DEBIAN_FRONTEND noninteractive

#Download all the packages needed

RUN apt-get update && apt-get install -y \
	build-essential \
	cmake \
	git \
	python \
	wget \
	unzip \
	bc\
	language-pack-en \
	curl \
    	libapr1-dev \
    	libaprutil1-dev \
    	libjansson-dev \
    	libxml2-dev \
    	libcurl4-openssl-dev \
	mercurial \
	zip \
	openjdk-7-jdk \
	libcups2-dev \
	libfreetype6-dev \
	libasound2-dev\
	libffi-dev \
	libX11-dev \
	libxext-dev \
	libxrender-dev \
	libxtst-dev \
	libxt-dev \
        && apt-get clean 

#Download and install the latest version of Docker (You need to be the same version to use this Dockerfile)

RUN wget -qO- https://get.docker.com/ | sh

#Prepare the usr directory by downloading in it : Buildroot, the configuration files of Buildroot, Apache Celix, Apache Felix, Apache Ace and Openjdk8

WORKDIR /usr

RUN wget http://git.buildroot.net/buildroot/snapshot/buildroot-2015.05.tar.gz && \
	tar -xf buildroot-2015.05.tar.gz && \
	git clone https://github.com/florian-gauvin/Buildroot-configure.git --branch celix buildroot-configure-celix && \
	git clone https://github.com/florian-gauvin/Buildroot-configure.git --branch ace buildroot-configure-ace && \
	wget https://github.com/apache/celix/archive/develop.tar.gz && \
	tar -xf develop.tar.gz && \
	mkdir celix-build && \
	wget http://www.eu.apache.org/dist/felix/org.apache.felix.main.distribution-5.0.1.tar.gz  && \
	tar -xf org.apache.felix.main.distribution-5.0.1.tar.gz && \
	wget http://www.eu.apache.org/dist/ace/apache-ace-2.0.1/apache-ace-2.0.1-bin.zip && \
	unzip apache-ace-2.0.1-bin.zip && \
	hg clone http://hg.openjdk.java.net/jdk8u/jdk8u openjdk8

#Let's begin with Apache Celix

#Copy the configuration file of Apache Celix in Buildroot and create a small base of the future image with buildroot and decompress it

RUN cp buildroot-configure-celix/.config buildroot-2015.05/

WORkDIR /usr/buildroot-2015.05

RUN make

WORKDIR /usr/buildroot-2015.05/output/images

RUN tar -xf rootfs.tar &&\
	rm rootfs.tar

#Build Celix and link against the libraries in the buildroot environment. It's not a real good way to do so but it's the only one that I have found : I remove the link.txt file and replace it by a one created manualy and not during the configuration, otherwise I don't have all the libraries linked against the environment in buildroot

WORKDIR /usr/celix-build

RUN cmake ../celix-develop -DWITH_APR=OFF -DCURL_LIBRARY=/usr/buildroot-2015.05/output/images/usr/lib/libcurl.so.4 -DZLIB_LIBRARY=/usr/buildroot-2015.05/output/images/usr/lib/libz.so.1 -DUUID_LIBRARY=/usr/buildroot-2015.05/output/images/usr/lib/libuuid.so -DBUILD_SHELL=TRUE -DBUILD_SHELL_TUI=TRUE -DBUILD_REMOTE_SHELL=TRUE -DBUILD_DEPLOYMENT_ADMIN=ON -DCMAKE_INSTALL_PREFIX=/usr/buildroot-2015.05/output/images/usr && \
	rm -f /usr/celix-build/launcher/CMakeFiles/celix.dir/link.txt && \
	echo "/usr/bin/cc  -D_GNU_SOURCE -std=gnu99 -Wall  -g CMakeFiles/celix.dir/private/src/launcher.c.o  -o celix -rdynamic ../framework/libcelix_framework.so /usr/buildroot-2015.05/output/images/lib/libpthread.so.0 /usr/buildroot-2015.05/output/images/lib/libdl.so.2 /usr/buildroot-2015.05/output/images/lib/libc.so.6 /usr/buildroot-2015.05/output/images/usr/lib/libcurl.so.4 ../utils/libcelix_utils.so -lm /usr/buildroot-2015.05/output/images/usr/lib/libuuid.so /usr/buildroot-2015.05/output/images/usr/lib/libz.so.1" > /usr/celix-build/launcher/CMakeFiles/celix.dir/link.txt && \
	make all && \
	make install-all 

# Create the config.properties file that celix will need in the futur small docker image

RUN echo "cosgi.auto.start.1= /usr/share/celix/bundles/deployment_admin.zip /usr/share/celix/bundles/log_service.zip /usr/share/celix/bundles/log_writer.zip /usr/share/celix/bundles/remote_shell.zip /usr/share/celix/bundles/shell.zip /usr/share/celix/bundles/shell_tui.zip" > /usr/buildroot-2015.05/output/images/usr/bin/config.properties


#We have all we need for the futur image so we can compress all the files, and store the tar file in a directory

WORKDIR /usr/buildroot-2015.05/output/images

RUN tar -cf rootfs.tar * && \
	mkdir /usr/celix-image && \
	cp rootfs.tar /usr/celix-image/

# Then the Apache ace image, copy the configuration file of Ace in Buildroot and create a small base of the future image with buildroot and decompress it

RUN cp -f /usr/buildroot-configure-ace/.config /usr/buildroot-2015.05/

WORkDIR /usr/buildroot-2015.05

RUN make clean all

WORKDIR /usr/buildroot-2015.05/output/images

RUN tar -xf rootfs.tar &&\
	rm rootfs.tar

#Compile the 3 compact profiles of Openjdk8, for more information about the compact profiles of openjdk8 see this link : http://openjdk.java.net/jeps/161

WORKDIR /usr/openjdk8

RUN bash ./get_source.sh && \
	export LIBFFI_CFLAGS=-I/usr/lib/x86_64-linux-gnu/include && \
	export LIBFFI_LIBS="-L/usr/lib/x86_64-linux-gnu/ -lffi" && \
	bash ./configure --with-jvm-variants=zero --enable-openjdk-only --with-freetype-include=/usr/include/freetype2 --with-freetype-lib=/usr/lib/x86_64-linux-gnu --with-extra-cflags=-Wno-error --with-extra-cxxflags=-Wno-error && \
	make profiles 

#Copy the built compact 2 profiles of openjdk8 and Apache-Ace in the Base image created with buildroot (We choose compact 2 for our project but you can copy an other compact profiles if you need by replacing "j2re-compact2-image" by "j2re-compact1-image" or "j2re-compact3-image"). Then we have all we need so we can compress all the files. Next the image is stored in a directory outside of buildroot

RUN cp -fr /usr/openjdk8/build/linux-x86_64-normal-zero-release/images/j2re-compact2-image /usr/buildroot-2015.05/output/images/usr/ && \
	cp -r /usr/apache-ace-2.0.1-bin /usr/buildroot-2015.05/output/images/usr && \
	cd /usr/buildroot-2015.05/output/images/ &&\
	tar -cf rootfs.tar * && \
	mkdir /usr/ace-image && \
	cp rootfs.tar /usr/ace-image && \
	rm rootfs.tar

#Finnally for Apache Felix, just replace the Apache Ace file by the Apache Felix one in the Buildroot environment because the buildroot configuration is the same, create the tar file and store it	

RUN rm -r /usr/apache-ace-2.0.1-bin && \
	cp -r /usr/felix-framework-5.0.1 /usr/buildroot-2015.05/output/images/usr/ && \
	tar -cf rootfs.tar * && \
	mkdir /usr/felix-image && \
	cp rootfs.tar /usr/felix-image

#When the builder image is launch, it creates the docker images automatically that you will be able to see by running the command : docker images

ENTRYPOINT for i in `seq 0 100`; do sudo mknod -m0660 /dev/loop$i b 7 $i; done && \
	service docker start && \
	docker import - celix.image < /usr/celix-image/rootfs.tar &&\
	docker import - felix.image < /usr/felix-image/rootfs.tar &&\
	docker import - ace.image < /usr/ace-image/rootfs.tar &&\
	/bin/bash 
