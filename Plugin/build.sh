#!/bin/bash
cd build
cmake ..
cmake --build . --config Debug
cmake --install . --config Debug
