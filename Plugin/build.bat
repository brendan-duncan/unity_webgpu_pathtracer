cd build
call cmake ..
call cmake --build . --config Release
call cmake --install . --config Release
cd ..
