# ArmConfigurationDrift
Script to check the differences between an Azure Resource Manager template and a deployed resource group

The script works by calling the `Test-AzureRmResourceGroupDeployment` command to expand an ARM template (merge parameters, evaluate functions etc.). It then calls `Get-AzureRmResource` to retrieve information about the resoures deployed in an existing Azure resource group. Finally it compares the two lists and reports on differences (resources present in one location but not the other, and property differences in matching resources).

Note that due to differences in the data structures used by the two APIs, the tool may miss some legitimate differences and may report false-positives. Some of these are unavoidable, but if you see any opportunities to improve accuracy then please log an issue or fix it and make a pull request.

## Usage
1. Log into Azure using `Login-AzureRmAccount` and select your subscription with `Select-AzureRmSubscription`
1. Load the script:`.\Show-AzureRmConfigurationDrift.ps1`
1. Run the `Show-AzureRmConfigurationDrift` function, passing in the names of your template file, template parameter file and resource group:
```powershell
+Show-AzureRmConfigurationDrift -resourceGroupName "myresourcegroup" -templateFile .\templates\azuredeploy.json -templateParametersFile .\templates\web-azuredeploy.parameters.json