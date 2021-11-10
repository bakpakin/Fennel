# See here for image contents: https://github.com/microsoft/vscode-dev-containers/tree/v0.205.1/containers/debian/.devcontainer/base.Dockerfile

# [Choice] Debian version (use bullseye or stretch on local arm64/Apple Silicon): bullseye, buster, stretch
ARG VARIANT="buster"
FROM mcr.microsoft.com/vscode/devcontainers/base:0-${VARIANT}

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    cloc \
    libc6-dev \
    libreadline-dev \
    gcc \
    make

ARG LUA_51=https://www.lua.org/ftp/lua-5.1.5.tar.gz
ARG LUA_52=https://www.lua.org/ftp/lua-5.2.4.tar.gz
ARG LUA_53=https://www.lua.org/ftp/lua-5.3.6.tar.gz
ARG LUA_54=https://www.lua.org/ftp/lua-5.4.3.tar.gz
ARG LUA_JIT=https://luajit.org/git/luajit.git
ARG LURAROCKS=https://luarocks.github.io/luarocks/releases/luarocks-3.8.0.tar.gz

RUN mkdir --parents /usr/local/src/lua51 && \
    curl "${LUA_51}" | tar -xz --directory=/usr/local/src/lua51 --strip-components=1 && \
    cd /usr/local/src/lua51 && make linux && make install INSTALL_TOP=/opt/lua51 && make clean && ln -s /opt/lua51/bin/lua /usr/local/bin/lua5.1
RUN mkdir --parents /usr/local/src/lua52 && \
    curl "${LUA_52}" | tar -xz --directory=/usr/local/src/lua52 --strip-components=1 && \
    cd /usr/local/src/lua52 && make linux && make install INSTALL_TOP=/opt/lua52 && make clean && ln -s /opt/lua52/bin/lua /usr/local/bin/lua5.2
RUN mkdir --parents /usr/local/src/lua53 && \
    curl "${LUA_53}" | tar -xz --directory=/usr/local/src/lua53 --strip-components=1 && \
    cd /usr/local/src/lua53 && make linux && make install INSTALL_TOP=/opt/lua53 && make clean &&ln -s /opt/lua53/bin/lua /usr/local/bin/lua5.3
RUN mkdir --parents /usr/local/src/lua54 && \
    curl "${LUA_54}" | tar -xz --directory=/usr/local/src/lua54 --strip-components=1 && \
    cd /usr/local/src/lua54 && make linux && make install INSTALL_TOP=/opt/lua54 && make clean && ln -s /opt/lua54/bin/lua /usr/local/bin/lua5.4
RUN git clone "${LUA_JIT}" /usr/local/src/luajit && \
    cd /usr/local/src/luajit && make PREFIX=/opt/luajit && make install PREFIX=/opt/luajit && make clean && mv /opt/luajit/bin/luajit* /opt/luajit/bin/luajit && ln -s /opt/luajit/bin/luajit /usr/local/bin/luajit

# Install luarocks into each environment
RUN mkdir --parents /usr/local/src/luarocks && \
    curl "${LURAROCKS}" | tar -xz --directory=/usr/local/src/luarocks --strip-components=1 && \
    cd /usr/local/src/luarocks && \
    ./configure --lua-version=5.1 --lua-suffix=5.1 --versioned-rocks-dir --with-lua=/opt/lua51 && make && make install && make clean && mv /usr/local/bin/luarocks /usr/local/bin/luarocks5.1 && \
    ./configure --lua-version=5.2 --lua-suffix=5.2 --versioned-rocks-dir --with-lua=/opt/lua52 && make && make install && make clean && mv /usr/local/bin/luarocks /usr/local/bin/luarocks5.2 && \
    ./configure --lua-version=5.3 --lua-suffix=5.3 --versioned-rocks-dir --with-lua=/opt/lua53 && make && make install && make clean && mv /usr/local/bin/luarocks /usr/local/bin/luarocks5.3 && \
    ./configure --lua-version=5.4 --lua-suffix=5.4 --versioned-rocks-dir --with-lua=/opt/lua54 && make && make install && make clean && mv /usr/local/bin/luarocks /usr/local/bin/luarocks5.4 && \
    ./configure --lua-suffix=luajit --versioned-rocks-dir --with-lua=/opt/luajit && make && make install && make clean && mv /usr/local/bin/luarocks /usr/local/bin/luarocksjit

# Configure default `lua` to lua5.4
RUN ln -s /usr/local/bin/lua5.4 /usr/local/bin/lua
# Configure default `luarocks` to lua5.4
RUN ln -s /usr/local/bin/luarocks5.4 /usr/local/bin/luarocks

# Install luacov for default luarocks
RUN luarocks install luacov
