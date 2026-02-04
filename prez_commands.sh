ls
./build.sh
docker build -t nautilus .
docker run --rm -it -p 80:80 -p 8090:8090 -p 45876:45876 nautilus
docker run -d --rm --name nautilus -p 80:80 -p 8090:8090 -p 45876:45876 nautilus
#nginx http://localhost/
#beszel http://localhost:8090/
docker run --rm -it --entrypoint /bin/sh nautilus

cat /etc/os-release
#0
busybox --list | head
ls -alht /bin

# Curl + nginx
curl http://172.17.0.1

# lua
lua -v
lua -e 'print("lua works:", 2+2)'

# jq
echo '{"service":"nginx","ok":true,"ports":[80,8090]}' | jq '.'
echo '{"service":"nginx","ok":true,"ports":[80,8090]}' | jq '.ports[0]'

# wyjście
exit

# odpalenie lua z poza konetenera
docker exec -it nautilus /bin/sh -c 'lua -v'

