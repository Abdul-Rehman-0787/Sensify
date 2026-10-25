# 1. Start from a base image that has C++ compilers installed
FROM gcc:latest

# 2. Set the working directory inside the container
WORKDIR /usr/src/app

# 3. Copy your local files into the container's working directory
COPY . .

# 4. Compile the C++ code
RUN g++ -o myapp main.cpp

# 5. Tell Docker what command to run when the container starts
CMD ["./myapp"]