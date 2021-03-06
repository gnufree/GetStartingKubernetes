#!/bin/sh

BASE_DOWNLOAD_SERVER=http://download.linux-dream.net	#important!!!  you must set the kubernetes archives download url

ETCD_ADDRESS=0.0.0.0
ECTD_PORT=4001
ETCD_PEER_PORT=7001

KUBE_API_ADDRESS=0.0.0.0
KUBE_API_PORT=8080

#controller manager config
MINION_ADDRESSES=192.168.1.3,192.168.1.4	#important!!!  you must set default minions node's address



#etcd config
ETCD_PEER_ADDR=${ETCD_ADDRESS}:7001		#important!!!  you must defined etcd server address
ETCD_ADDR=${ETCD_ADDRESS}:4001
ETCD_DATA_DIR=/var/lib/etcd
ETCD_NAME=kubernetes

#apiserver config
MY_IP=$(hostname -I | awk '{print $1}')
KUBE_ETCD_SERVERS=http://${ETCD_ADDR}
MINION_PORT=10250
KUBE_ALLOW_PRIV=false
KUBE_SERVICE_ADDRESSES=10.100.0.0/16

#kube common config
KUBE_LOGTOSTDERR=true
KUBE_LOG_LEVEL=4
KUBE_MASTER=${KUBE_API_ADDRESS}:${KUBE_API_PORT}	#important!!!  you must set kube server address for other component

downloadkubernetes(){
	test -d /opt/kubernetes-master && rm -rf /opt/kubernetes-master
	echo "start download kubernetes archives..."
	wget ${BASE_DOWNLOAD_SERVER}/archives/kubernetes/kubernetes-master.tar.gz -O /opt/kubernetes-master.tar.gz

	cd /opt/

	tar -vxzf kubernetes-master.tar.gz

	cd ../
	rm -rf /opt/kubernetes-master.tar.gz
}

install_Etcd(){
	echo "start install Etcd..."
	test -f /usr/bin/etcd && rm -rf /usr/bin/etcd
	test -f /usr/bin/etcdctl && rm -rf /usr/bin/etcdctl

	wget ${BASE_DOWNLOAD_SERVER}/archives/etcd/etcd -O /usr/bin/etcd 
	wget ${BASE_DOWNLOAD_SERVER}/archives/etcd/etcdctl -O /usr/bin/etcdctl

	chmod 755 /usr/bin/etcd*

	! test -d $ETCD_DATA_DIR && mkdir -p $ETCD_DATA_DIR
	cat <<-EOF>/usr/lib/systemd/system/etcd.service
	[Unit]
	Description=Etcd Server
	After=network.service
	Requires=network.service

	[Service]
	ExecStart=/usr/bin/etcd -peer-addr=$ETCD_PEER_ADDR -addr=$ETCD_ADDR -data-dir=$ETCD_DATA_DIR -name=$ETCD_NAME

	[Install]
	WantedBy=multi-user.target
	EOF

	systemctl daemon-reload
	systemctl stop etcd
	systemctl start etcd
	systemctl enable etcd

	echo "Etcd install successfull!"
}

install_KubeApiserver(){
	echo "start install KubeApiserver..."
	cat <<-EOF>/usr/lib/systemd/system/kube-apiserver.service
	[Unit]
	Description=Kubernetes API Server
	Documentation=https://github.com/GoogleCloudPlatform/kubernetes
	After=etcd.service
	Requires=etcd.service

	[Service]
	ExecStart=/opt/kubernetes-master/kube-apiserver --logtostderr=${KUBE_LOGTOSTDERR} --v=${KUBE_LOG_LEVEL} --etcd_servers=${KUBE_ETCD_SERVERS} --address=${KUBE_API_ADDRESS} --port=${KUBE_API_PORT} --kubelet_port=${MINION_PORT} --allow_privileged=${KUBE_ALLOW_PRIV} --cors_allowed_origins=.* --portal_net=${KUBE_SERVICE_ADDRESSES}

	Restart=on-failure	

	[Install]
	WantedBy=multi-user.target
	EOF

	systemctl daemon-reload
	systemctl stop kube-apiserver
	systemctl start kube-apiserver
	systemctl enable kube-apiserver
	ln -s /opt/kubernetes-master/kubectl /usr/bin/kubectl
	echo "KubeApiserver install successfull!"
}


install_KubeControllerManager(){
	echo "start install KubeControllerManager..."
	cat <<-EOF>/usr/lib/systemd/system/kube-controller-manager.service
	[Unit]
	Description=Kubernetes Controller Manager
	Documentation=https://github.com/GoogleCloudPlatform/kubernetes
	After=kube-apiserver.service
	Requires=kube-apiserver.service

	[Service]
	ExecStart=/opt/kubernetes-master/kube-controller-manager --logtostderr=${KUBE_LOGTOSTDERR} --v=${KUBE_LOG_LEVEL} --machines=${MINION_ADDRESSES} --master=${KUBE_MASTER}
	Restart=on-failure

	[Install]
	WantedBy=multi-user.target
	EOF

	systemctl daemon-reload
	systemctl stop kube-controller-manager
	systemctl start kube-controller-manager
	systemctl enable kube-controller-manager

	echo "KubeControllerManager install successfull!"
}


install_KubeScheduler(){
	echo "start install KubeScheduler..."
	cat <<-EOF>/usr/lib/systemd/system/kube-scheduler.service
	[Unit]
	Description=Kubernetes Scheduler
	Documentation=https://github.com/GoogleCloudPlatform/kubernetes
	After=kube-apiserver.service
	Requires=kube-apiserver.service

	[Service]
	ExecStart=/opt/kubernetes-master/kube-scheduler --logtostderr=${KUBE_LOGTOSTDERR} --v=${KUBE_LOG_LEVEL} --master=${KUBE_MASTER}
	Restart=on-failure

	[Install]
	WantedBy=multi-user.target
	EOF

	systemctl daemon-reload
	systemctl stop kube-scheduler
	systemctl start kube-scheduler
	systemctl enable kube-scheduler

	echo "KubeScheduler install successfull!"
}

applyIptablesRules(){
	systemctl start iptables
	iptables -I INPUT -p tcp --dport ${KUBE_API_PORT} -j ACCEPT
	iptables -I OUTPUT -p tcp --dport ${KUBE_API_PORT} -j ACCEPT
	iptables -I INPUT -p tcp --dport ${ECTD_PORT} -j ACCEPT
	iptables -I OUTPUT -p tcp --dport ${ECTD_PORT} -j ACCEPT
	iptables -I INPUT -p tcp --dport ${ETCD_PEER_PORT} -j ACCEPT
	iptables -I OUTPUT -p tcp --dport ${ETCD_PEER_PORT} -j ACCEPT
	iptables-save > /etc/sysconfig/iptables	
	systemctl restart iptables

	echo "Apply iptables rules successfull!"
}

downloadkubernetes

install_Etcd

install_KubeApiserver

install_KubeControllerManager

install_KubeScheduler

applyIptablesRules
