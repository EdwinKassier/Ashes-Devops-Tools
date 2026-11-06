
# create_organization_trail put the trail module behind count.
moved {
  from = module.cloudtrail
  to   = module.cloudtrail[0]
}
