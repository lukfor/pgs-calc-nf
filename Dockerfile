FROM continuumio/miniconda3
MAINTAINER Lukas Forer <lukas.forer@i-med.ac.at>

COPY environment.yml .
RUN \
   conda env update -n root -f environment.yml \
&& conda clean -a

# Install jbang (not as conda package available)
WORKDIR "/opt"
RUN wget https://github.com/jbangdev/jbang/releases/download/v0.59.0/jbang.zip && \
    unzip -q jbang.zip && \
    rm jbang.zip
ENV PATH="/opt/jbang/bin:${PATH}"

# Install pgs-calc (not as conda package available)
RUN mkdir /opt/pgs-calc
WORKDIR "/opt/pgs-calc"
RUN wget https://github.com/lukfor/pgs-calc/releases/download/v0.9.6/installer.sh && \
    chmod +x installer.sh && \
    ./installer.sh
ENV PATH="/opt/pgs-calc:${PATH}"
