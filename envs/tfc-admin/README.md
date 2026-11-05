# tfc-admin

Declares the whole Terraform Cloud workspace layer as code (audit C3): every
deployable root's workspace, its working directory, VCS wiring, tags, and shared
variables, driven by the same `environments` map the cloud roots consume.

Previously these workspaces were hand-created in the TFC UI, which left them
unversioned, unreviewable, and invisible to drift detection. This root fixes that.

It declares NO cloud provider, so it needs no cloud credentials, only a TFC token
(`TFE_TOKEN`). Apply it after creating its own `tfc-admin` workspace by hand once
(the one bootstrap step), then it manages all the others.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
