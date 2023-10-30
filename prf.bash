#!/bin/bash

rm build/profile.ncu-rep -f

#/usr/local/cuda-12.3/bin/ncu -h 

sudo /usr/local/cuda-12.3/bin/ncu -f -o build/profile build/a.out 
