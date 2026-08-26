output "instructions" {
  value = <<-EOT
Update Kubeconfig:
------------------
Run this command to update ~/.kube/config file: 'aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}'


To Login ArgoCD:
----------------
1) Run this command: 'kubectl get ingress -n argocd' and uses the ADDRESS from 'argocd-server'
2) Uses user 'admin'
3) Password run this command to get the initial password: 'kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d'

Go Hit 10 App:
--------------
After deploy on ArgoCD, Run this command: 'kubectl get httproutes.gateway.networking.k8s.io -n counter-api' and uses the HOSTNAMES from 'counter-api' and uses it on you hosts file with your NLB address.


To Destroy:
-----------
Do this steps to destroy all:

1) terraform destroy

EOT
}
