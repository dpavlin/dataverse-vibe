#!/bin/sh -xe

# https://github.com/IQSS/dataverse/releases/tag/v6.1

cd v6.1

# dpavlin@deb-crossda-test:~/v6.1$

../dv-upgrade.sh dataverse-6.1.war

curl http://localhost:8080/api/admin/datasetfield/load -H "Content-type: text/tab-separated-values" -X POST --upload-file geospatial.tsv

curl http://localhost:8080/api/admin/datasetfield/load -H "Content-type: text/tab-separated-values" -X POST --upload-file citation.tsv

# solr 

tail -f /usr/local/solr/server/logs/*.log &

service solr stop
systemctl stop solr

sudo cp -v schema.xml /usr/local/solr/server/solr/collection1/conf/

systemctl start solr

grep alternativeTitle /usr/local/solr/server/solr/collection1/conf/schema.xml





