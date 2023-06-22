FROM ubuntu:jammy
LABEL maintainer="TUNBudi06 <anjaytun2006@gmail.com>"
ENV DEBIAN_FRONTEND noninteractive

WORKDIR /tmp

RUN apt-get -yqq update \
    && apt-get -yqq upgrade \
    && apt-get install -y git sudo neofetch unzip apt-utils curl wget 

RUN wget https://dl.google.com/android/repository/platform-tools-latest-linux.zip \
    && unzip platform-tools-latest-linux.zip -d /tmp/ \
    && export PATH="/tmp/platform-tools:$PATH"
    
RUN cd /tmp \
  && git clone https://github.com/akhilnarang/scripts \
  && cd scripts \
  && bash setup/android_build_env.sh

RUN mkdir -p /tmp/bin 

RUN curl https://storage.googleapis.com/git-repo-downloads/repo > /tmp/bin/repo \
  && chmod a+x /tmp/bin/repo && export PATH="/tmp/bin:$PATH"

RUN git clone https://github.com/facebook/zstd.git && cd zstd && git reset --hard f349d18 \
    && mkdir build/cmake/build && cd build/cmake/build \
    && cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release .. \
    && make CFLAGS="-O3" && sudo make install

RUN git clone https://github.com/google/brotli.git \
    && cd brotli && mkdir out && cd out && ../configure-cmake --disable-debug \
    && make CFLAGS="-O3" && sudo make install

RUN git clone https://github.com/redis/hiredis.git && cd hiredis && git reset --hard 95a0c12 \
    && mkdir build && cd build && cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release .. \
    && make CFLAGS="-O3" && sudo make install


RUN git clone https://github.com/ccache/ccache.git && cd ccache && git reset --hard 8c2da59 \
    && mkdir build && cd build && cmake -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release .. \
    && make CFLAGS="-O3" && sudo make install

RUN export CCACHE_DIR=/tmp/ccache && \
	export CCACHE_EXEC=$(which ccache) && \
	ccache -s

VOLUME ["/tmp/bin", "/tmp/rom"]
ENTRYPOINT ["/bin/bash"]
