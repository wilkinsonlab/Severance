timestamp=$(date +"%Y-%m-%d")

rm -rf ./secury_scan_output/*.json

# Severance Internal
image="fairdatasystems/severance-internal:latest"
name="sevinternal"
docker rm ${name}

outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
echo "running docker run -d --name ${name} ${image} ${outputfile}"
docker run -d --name ${name} ${image}
echo ""
echo ""
# use the appropriate distribution upgrade tool for that container’s operating system
echo "updating ${name}"
echo "update"
docker exec -it ${name} apt-get -y update 
echo "dist-upgrade"
docker exec -it ${name} apt-get -y dist-upgrade --fix-missing
echo "autoclean"
docker start ${name}
docker exec -it ${name} apt-get -y autoclean
# Commit the patched container, with a new name, overwriting the previous version
echo "commit"
docker commit ${name} fairdatasystems/${name}:${timestamp}
# stop the temporary container
docker stop ${name}
# delete the temporary container
docker rm ${name}
echo "push"
docker push fairdatasystems/${name}:${timestamp}
echo "pushed"
SIN="fairdatasystems/${name}:${timestamp}"
# run a scan to determine success
echo "trivy"
trivy image --scanners vuln --format json --severity CRITICAL,HIGH  --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
echo "END"


# Severance External
image="fairdatasystems/severance-external:latest"
name="sevexternal"
docker rm ${name}
outputfile=("./security_scan_output/scanresults_${name}_${timestamp}.json")
echo "running docker run -d --name ${name} ${image} ${outputfile}"
docker run -d --name ${name} ${image}
# use the appropriate distribution upgrade tool for that container’s operating system
echo ""
echo ""
echo "updating ${name}"
echo "update"
docker exec -it ${name} apt-get -y update 
echo "dist-upgrade"
docker exec -it ${name} apt-get -y dist-upgrade --fix-missing
echo "autoclean"
docker start ${name}
docker exec -it ${name} apt-get -y autoclean
# Commit the patched container, with a new name, overwriting the previous version
echo "commit"
docker commit ${name} fairdatasystems/${name}:${timestamp}
# stop the temporary container
docker stop ${name}
# delete the temporary container
docker rm ${name}
echo "push"
docker push fairdatasystems/${name}:${timestamp}
echo "pushed"
SOUT="fairdatasystems/${name}:${timestamp}"
# run a scan to determine success
echo "trivy"
trivy image --scanners vuln  --format json  --severity CRITICAL,HIGH --timeout 1800s fairdatasystems/${name}:${timestamp}  > ${outputfile}
echo "END"

cp inner-docker-compose-template-template.yml inner-docker-compose-template-tmp.yml
cp outer-docker-compose-template-template.yml outer-docker-compose-template-tmp.yml
sed -i'' -e "s!{SIN}!${SIN}!" "inner-docker-compose-template-tmp.yml"
sed -i'' -e "s!{SOUT}!${SOUT}!" "outer-docker-compose-template-tmp.yml"

mv inner-docker-compose-template-tmp.yml ../internal/docker-compose.yml
mv outer-docker-compose-template-tmp.yml ../external/docker-compose.yml

ruby parse-security-scans.rb ./security_scan_output/*.json
