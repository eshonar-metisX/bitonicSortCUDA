import numpy as np
from matplotlib import pyplot

# f = open("res.txt", 'r')

# idx = np.array([])
# a = np.array([])

# i = 0

# for line in f:

#     idx = np.append(idx, i)
#     a = np.append(a, float(line.split(" ")[1]))

#     i+=1
    #print(line.split(" ")[1])

#f.close()

idx, a = np.loadtxt("unsorted.txt", delimiter = " ", dtype='float', unpack=True, usecols={0, 1})

pyplot.scatter(idx,a)
pyplot.tight_layout()
pyplot.savefig('unsorted.jpg')