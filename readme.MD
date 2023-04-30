# The Ashes Project Devops Tools

As part of the ongoing development of the Ashes project I thought I would start setting out and documenting the infrastructure of the project.

I am doing this for one main reason: should I ever lose access to my cloud environment I need to have a way to rebuild that environment very quickly without the hassle of doing everything through the GCP UI. This repo then sets out the terraform code I would need to fully recreate and manage my cloud infrastructure environment and all of my projects.

This system dovetails into the CI/CD actions set out in my code repos, allowing a seamless transition from one project to another, barring any smaller credentials and configuration updates needed.

<br />

## My Infrastructure Mantras

1. Noone cares how fancy or complex your infrastructure is, they only care that it works, and that it works reliably. Simplicity is paramount
2. If you're having to do regular maintenance to make sure it continues to work, you're doing it wrong
3. Managed scaling and managed environments are King, it is unlikely that you can outdo the entire teams managing those environments for you
4. Always use containers where possible, nothing is worse than debugging different environments
5. If someone else with limited knowledge can't easily take charge of your infrastructure from you, you're doing it wrong

<br />

# Getting Started

To protect my cloud environment I have not included any secrets or particulars to my project in this repo, that all only lives in my secret management system. So should you want to run this and you're not me you will have to add in your own init.tf file. Allowing Terraform a place to initialise itself and properly connect to your environment. This terraform repo centers around GCP, so if you're coming from an AWS background I'll mark down some alternatives later on in this readme.

Here is an example of the init.tf file you should be creating in the root folder:


    terraform {
    required_providers {
        google = {
        source = "hashicorp/google"
        version = "4.51.0"
        }
    }
    }

    provider "google" {
    project     = {your project name: string}
    region      = {your project region: string}
    }

In addition to creating this you will need to link your GCP credentials to your command line, or you can provide service account credentials in the init file itself.

## How to run the Terraform scripts

If you have done your setup correctly, you can run: 

`terraform plan`

This will show you what will happen (what will be created or updated) if you run the terraform script.

If you are happy with these changes, you can run:

`terraform apply`

This will go ahead and provision/update your cloud resources.

<br />

# The Ashes Project Design

![Alt text](AshesDesign.png?raw=true "Title")
