cd build
call cmake ..
call cmake --build . --config Debug
call cmake --install . --config Debug
cd ..
