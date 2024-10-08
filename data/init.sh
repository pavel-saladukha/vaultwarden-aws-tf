#!/bin/bash

token=$(curl --ipv6 -X PUT "http://[fd00:ec2::254]/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
export ipv4=$(curl --ipv6 -H "X-aws-ec2-metadata-token: $token" http://[fd00:ec2::254]/latest/meta-data/public-ipv4)
echo $ipv4
hosted_zone_id=$(aws route53 list-hosted-zones | jq -r '.HostedZones.[] | select (.Name == "${hosted_zone}.") | .Id' | cut -d/ -f3)
cat >> ./route53_draft.json << 'EOF'
{
	"Changes": [
		{
			"Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "${full_domain_name}",
                "Type": "A",
	            "TTL": 60,
             	"ResourceRecords": [
             		{ "Value": "$ipv4"}
         		]
			}
		}
	]
}
EOF
envsubst < route53_draft.json > route53.json
aws route53 change-resource-record-sets --hosted-zone-id $hosted_zone_id --change-batch file://route53.json

yum check-update
yum update -y

yum install -y jq tree git python3-devel

# Docker and docker-compose
yum update -y
yum install -y docker
usermod -aG docker ec2-user
systemctl enable docker.service
systemctl start docker.service
export ENV_DOCKER_COMPOSE_VERSION="v2.29.1"
curl -L "https://github.com/docker/compose/releases/download/$ENV_DOCKER_COMPOSE_VERSION/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
chmod a+x /usr/local/bin/docker-compose
ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose

# Fail2Ban to minimize ddos and brute-force passwords
git clone https://github.com/fail2ban/fail2ban.git --branch 1.1.0
cd fail2ban
python3 setup.py build
python3 setup.py install
cp ./build/fail2ban.service /etc/systemd/system/fail2ban.service
sed -i '/PYTHONNOUSERSITE/a Environment="PYTHONPATH=/usr/local/lib/python3.9/site-packages"' /etc/systemd/system/fail2ban.service
systemctl enable fail2ban
# Filter and jail for Vaultwarden
aws s3 cp s3://${s3_configs}/vaultwarden-jail.conf /etc/fail2ban/jail.d/vaultwarden.conf --sse
aws s3 cp s3://${s3_configs}/vaultwarden-filter.conf /etc/fail2ban/filter.d/vaultwarden.conf --sse
# Filter and jail for Vaultwarden admin page
aws s3 cp s3://${s3_configs}/vaultwarden-admin-jail.conf /etc/fail2ban/jail.d/vaultwarden-admin.conf --sse
aws s3 cp s3://${s3_configs}/vaultwarden-admin-filter.conf /etc/fail2ban/filter.d/vaultwarden-admin.conf --sse
# Jails for Nginx
aws s3 cp s3://${s3_configs}/nginx-botsearch-jail.conf /etc/fail2ban/jail.d/nginx-botsearch.conf --sse
aws s3 cp s3://${s3_configs}/nginx-http-auth-jail.conf /etc/fail2ban/jail.d/nginx-http-auth.conf --sse
# 301
aws s3 cp s3://${s3_configs}/nginx-301-jail.conf /etc/fail2ban/jail.d/nginx-301.conf --sse
aws s3 cp s3://${s3_configs}/nginx-301-filter.conf /etc/fail2ban/filter.d/nginx-301.conf --sse
# 400
aws s3 cp s3://${s3_configs}/nginx-400-jail.conf /etc/fail2ban/jail.d/nginx-400.conf --sse
aws s3 cp s3://${s3_configs}/nginx-400-filter.conf /etc/fail2ban/filter.d/nginx-400.conf --sse
# 404
aws s3 cp s3://${s3_configs}/nginx-404-jail.conf /etc/fail2ban/jail.d/nginx-404.conf --sse
aws s3 cp s3://${s3_configs}/nginx-404-filter.conf /etc/fail2ban/filter.d/nginx-404.conf --sse

systemctl reload fail2ban

# Certbot
yum install -y certbot
yum update -y
yum install -y certbot-dns-route53
certbot certonly \
	--dns-route53 --dns-route53-propagation-seconds 30 \
	--domain ${full_domain_name} -m ${email_for_cert} \
	--key-type ecdsa \
	--agree-tos \
	--non-interactive --quiet ${enable_test_cert}

# Crons
home_dir="/home/ec2-user"
export home_dir
scripts_path="$home_dir/scripts"
export scripts_path
mkdir -p $scripts_path

cat >> /etc/cron.d/change-eni << 'EOF'
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
@reboot root ip route del default dev eth0 > /dev/null 2>&1
EOF

cat >> /etc/cron.d/backup-vaultwarden.tmp << 'EOF'
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
0 1 * * * ec2-user bash $scripts_path/backup.sh &> /dev/null 2>&1
EOF
envsubst < /etc/cron.d/backup-vaultwarden.tmp > /etc/cron.d/backup-vaultwarden
rm /etc/cron.d/backup-vaultwarden.tmp
aws s3 cp s3://${s3_configs}/backup.sh $scripts_path/backup.sh --sse
chmod a+x $scripts_path/backup.sh

cat >> /etc/cron.d/update-packages.tmp << 'EOF'
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
0 2 */7 * * root bash $scripts_path/update.sh &> /dev/null 2>&1
EOF
envsubst < /etc/cron.d/update-packages.tmp > /etc/cron.d/update-packages
rm /etc/cron.d/update-packages.tmp
aws s3 cp s3://${s3_configs}/update.sh $scripts_path/update.sh --sse
chmod a+x $scripts_path/update.sh

cat >> /etc/cron.d/maintenance.tmp << 'EOF'
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
0 3 * */ * root bash $scripts_path/maintenance.sh &> /dev/null 2>&1
EOF
envsubst < /etc/cron.d/maintenance.tmp > /etc/cron.d/maintenance
rm /etc/cron.d/maintenance.tmp
aws s3 cp s3://${s3_configs}/maintenance.sh $scripts_path/maintenance.sh --sse
chmod a+x $scripts_path/maintenance.sh

cat >> /etc/cron.d/renew-certs << 'EOF'
SHELL=/bin/bash
PATH=/sbin:/bin:/usr/sbin:/usr/bin
0 4 * */ * root certbot renew &> /dev/null 2>&1
EOF

#  Gracefully shutdown the app if the instance is scheduled for termination
aws s3 cp "s3://${s3_configs}/AWS_SpotTerminationNotifier.sh" $scripts_path/AWS_SpotTerminationNotifier.sh
chmod a+x $scripts_path/AWS_SpotTerminationNotifier.sh
screen -dm -S AWS_SpotTerminationNotifier $scripts_path/AWS_SpotTerminationNotifier.sh

# NGINX config
nginx_config_path="$home_dir/nginx"
mkdir -p $nginx_config_path
touch $nginx_config_path/access.log
touch $nginx_config_path/error.log
cp /etc/letsencrypt/live/${full_domain_name}/privkey.pem $nginx_config_path/privkey.pem
cp /etc/letsencrypt/live/${full_domain_name}/fullchain.pem $nginx_config_path/fullchain.pem
aws s3 cp s3://${s3_configs}/nginx.conf $nginx_config_path/nginx.conf --sse
aws s3 cp s3://${s3_configs}/Dockerfile $nginx_config_path/Dockerfile --sse
aws s3 cp s3://${s3_configs}/docker-compose.yml $home_dir/docker-compose.yml --sse

yum update -y && yum install -y sqlite-devel
docker-compose -f $home_dir/docker-compose.yml up --build -d
sleep 15
docker-compose -f $home_dir/docker-compose.yml down --volumes

chown -R ec2-user:ec2-user /home/ec2-user

# Try to re-apply latest backup
cd $home_dir
aws s3 cp s3://${s3_backups}/backup-latest.tar.gz $home_dir/latest.tar.gz --sse
if [[ -f $home_dir/latest.tar.gz ]]
	then
	rm -rf $home_dir/vw-data
	tar -xf $home_dir/latest.tar.gz
		
	sqlite3 $home_dir/vw-data/db.sqlite3 ".restore '$home_dir/vw-data/backup.sqlite3'"

	rm $home_dir/latest.tar.gz
	rm $home_dir/vw-data/backup.sqlite3	

fi

docker-compose -f $home_dir/docker-compose.yml up -d

sleep 15

hostnamectl set-hostname warden

# Force reboot
shutdown -r now
