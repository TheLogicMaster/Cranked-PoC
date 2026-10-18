# Build environment for the Proof of Concept targets: Linux desktop and libretro (JIT and interpreter), web
# (Emscripten), the libretro core for Android (with WITH_ANDROID=1), the runner, and the Linux AppImage.
# Used by scripts/docker-build.sh; the Playdate SDK is mounted at run time, never copied into the image.
FROM ubuntu:24.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential cmake ninja-build git python3 curl ca-certificates xz-utils unzip zip file pkg-config \
      libgl-dev libegl-dev libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxi-dev libxinerama-dev \
      libxss-dev libxfixes-dev libwayland-dev libxkbcommon-dev libdecor-0-dev libasound2-dev libpulse-dev \
      libdbus-1-dev libudev-dev \
    && rm -rf /var/lib/apt/lists/*

# Emscripten, the version the web build was made and tested with
ARG EMSDK_VERSION=3.1.52
RUN git clone --depth 1 https://github.com/emscripten-core/emsdk.git /opt/emsdk \
    && cd /opt/emsdk && ./emsdk install $EMSDK_VERSION && ./emsdk activate $EMSDK_VERSION \
    && chmod -R a+rX /opt/emsdk
ENV EMSDK=/opt/emsdk

# The Android NDK, only when asked for (about 2 GB): docker build --build-arg WITH_ANDROID=1
ARG WITH_ANDROID=0
ARG ANDROID_NDK_VERSION=r27c
RUN if [ "$WITH_ANDROID" = 1 ]; then \
      curl -sSL -o /tmp/ndk.zip https://dl.google.com/android/repository/android-ndk-$ANDROID_NDK_VERSION-linux.zip \
      && unzip -q /tmp/ndk.zip -d /opt && rm /tmp/ndk.zip && ln -s /opt/android-ndk-$ANDROID_NDK_VERSION /opt/android-ndk; \
    fi
ENV ANDROID_NDK_HOME=/opt/android-ndk

# appimagetool, run without FUSE
RUN curl -sSL -o /usr/local/bin/appimagetool \
      https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$(uname -m).AppImage \
    && chmod +x /usr/local/bin/appimagetool
ENV APPIMAGE_EXTRACT_AND_RUN=1

# Runs as the caller's user (scripts/docker-build.sh passes --user): caches go to the mounted tree
ENV HOME=/tmp EM_CACHE=/src/build/emscripten-cache
RUN git config --system --add safe.directory '*'
WORKDIR /src
