#!/usr/bin/env bash

# create topic, the property is `redpanda.kvstore=cloud|none`
docker compose exec redpanda-0 /opt/redpanda/bin/rpk topic create example-topic -c 'redpanda.kvstore=cloud'
echo "producing to topic"
printf "foo bar\nhello world\nfoo qux\n" | docker compose exec -T redpanda-0 /opt/redpanda/bin/rpk topic produce example-topic -f '%k %v\n'
echo "consuming from topic"
docker compose exec redpanda-0 /opt/redpanda/bin/rpk topic consume example-topic -o :end
echo "doing kvstore lookup"
docker compose exec redpanda-0 /opt/redpanda/bin/rpk kvstore get example-topic foo
echo "doing kvstore scan"
docker compose exec redpanda-0 /opt/redpanda/bin/rpk kvstore scan example-topic
