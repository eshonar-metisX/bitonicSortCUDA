#!/bin/bash

nvcc -std=c++17 -ltbb -O2 -rdc=true -o build/a.out bitonicSort.cu