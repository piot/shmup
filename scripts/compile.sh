
cp ../../swamp/mangrove/target/perf/mangrove build/macos/Shmup.app/Contents/MacOS/
cp mangrove.yini build/macos/Shmup.app/Contents/Resources/
cp mangrove.local.yini build/macos/Shmup.app/Contents/Resources/
cp -r assets build/macos/Shmup.app/Contents/Resources/

tree build/macos/Shmup.app

( # sub shell block is very important
    cd ./build/macos/Shmup.app/Contents/MacOS/
    RUST_LOG=info ./mangrove
)

# ~/Downloads/butler-darwin-amd64/butler push ./build/macos lily2d/shmup:test-macos
