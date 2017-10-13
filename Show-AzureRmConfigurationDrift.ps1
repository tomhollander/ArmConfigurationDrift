function ExpandTemplate
{

    param (
        $resourceGroupName,
        $templateFile,
        $templateParametersFile
    )

    $debugPreference = 'Continue'
    $rawResponse = Test-AzureRmResourceGroupDeployment -TemplateFile $templateFile -TemplateParameterFile $templateParametersFile -ResourceGroupName $resourceGroupName 5>&1
    $debugPreference = 'SilentlyContinue'
    $httpResponse = $rawResponse | Where { $_ -like "*HTTP RESPONSE*"} | ForEach-Object {$_ -Replace 'DEBUG: ', ''}
    $armTemplateJson = '{' + $httpResponse.Split('{',2)[1]
    $armTemplateObject = $armTemplateJson | ConvertFrom-Json


    # Validated Resources in PowerShell object
    $resources = @()

    # Fix names that don't match the RG ones
    foreach ($res in $armTemplateObject.properties.validatedResources) 
    {
        $res | Add-Member -MemberType NoteProperty -Name "ResourceId" -Value $res.id
        $res | Add-Member -MemberType NoteProperty -Name "ResourceType" -Value $res.type
        $resources += $res
    }

    return $resources

}

function GetResourcesInRG
{
    param (
        $resourceGroupName
    )
    $debugPreference = 'SilentlyContinue'
    $currentSubscriptionId = (Get-AzureRmContext).Subscription.SubscriptionId
    $resources = Get-AzureRmResource -ResourceId "/subscriptions/$currentSubscriptionId/resourceGroups/$resourceGroupName/resources" -ExpandProperties
    return $resources

}

function MatchProperties
{
    param (
        $resourceId,
        $templateResource,
        $rgResource
    )

    $templateResourceProps = $templateResource | Get-Member -MemberType NoteProperty | Select -ExpandProperty Name
    foreach ($propName in $templateResourceProps)
    {
         $templateResourcePropValue = $templateResource."$propName"
         $rgResourcePropValue = $rgResource."$propName"
         if ($rgResourcePropValue -eq $null) 
         {
            # Skip if the props don't match, report on the non-obvious ones
            if ($propName -ne "apiVersion" -and $propName -ne "id" -and $propName -ne "type" -and $propName -ne "dependsOn")
            {
                Write-Host "`tSkipping property '$propName' from template, as it could not be found on the deployed resource." -ForegroundColor Gray
            }
         } 
         else
         {
            # Property found on both sides, so compare values
            if ($templateResourcePropValue.GetType().Name -eq "PSCustomObject")
            {
                # Recurse to the next level
                MatchProperties -resourceId $resourceId -templateResource $templateResourcePropValue  -rgResource $rgResourcePropValue
            }
            elseif ($templateResourcePropValue.GetType().Name -eq "Object[]")
            {
                if ($templateResourcePropValue.Length -ne $rgResourcePropValue.Length)
                {
                     Write-Host "`tMismatch in property '$propName'. Different number of elements in arrays." -ForegroundColor Yellow
                }
                else
                {
                    for ($i=0 ; $i -lt $templateResourcePropValue.Length; $i++)
                    {
                        if ($templateResourcePropValue[$i].GetType().Name -eq "PSCustomObject")
                        {
                            MatchProperties -resourceId $resourceId -templateResource $templateResourcePropValue[$i]  -rgResource $rgResourcePropValue[$i]
                        }
                        else
                        {
                            if ((CompareProps -propName $propName -propValue1 $templateResourcePropValue[$i] -propValue2 $rgResourcePropValue[$i]) -eq $false)
                            {
                                Write-Host "`tMismatch in property '$propName[$i]'. Value in template: '$($templateResourcePropValue[$i])', value in deployed resource: '$($rgResourcePropValue[$i])' " -ForegroundColor Yellow
                            }
                        }
                    }
                }
            }
            else
            {
                if ( (CompareProps -propName $propName -propValue1 $templateResourcePropValue -propValue2 $rgResourcePropValue) -eq $false)
                {
                    Write-Host "`tMismatch in property '$propName'. Value in template: '$templateResourcePropValue', value in deployed resource: '$rgResourcePropValue' " -ForegroundColor Yellow
                }
            }
         }
    }

}

function CompareResourceLists
{
    param (
        $templateResources,
        $rgResources
    )

    # Check for resources in template but not RG
    foreach ($templateRes in $templateResources)
    {
        $rgRes = $rgResources | Where-Object { $_.ResourceId -eq $templateRes.ResourceId } 
        if ($rgRes -eq $null)
        {
            Write-Host "Resource from template $($templateRes.ResourceId) not present in Resource Group" -ForegroundColor Magenta
        }
    }

    # Check for resources in resourceList2 but not resourceList1
    foreach ($rgRes in $rgResources)
    {
        $templateRes = $templateResources | Where-Object { $_.ResourceId -eq $rgRes.ResourceId } 
        if ($templateRes -eq $null)
        {
            Write-Host "Resource in RG $($rgRes.ResourceId) not present in template" -ForegroundColor Green
        }
    }

    # Find resources that exist in both lists
    foreach ($templateRes in $templateResources)
    {
        $rgRes = $rgResources | Where-Object { $_.ResourceId -eq $templateRes.ResourceId } 
        if ($rgRes -ne $null)
        {
            Write-Host "Comparing properties in resource $($rgRes.ResourceId)"
            MatchProperties -resourceId $templateRes.ResourceId -templateResource $templateRes -rgResource $rgRes

        }
    }
}

$locations = Get-AzureRmLocation

function CompareProps($propName, $propValue1, $propValue2)
{
    if ($propName -eq "location")
    {
        return CompareLocations -loc1 $propValue1 -loc2 $propValue2
    }
    else
    {
        return $propValue1 -eq $propValue2
    }
}

function CompareLocations($loc1, $loc2)
{
    # Check if 2 location strings refer to the same region, e.g. "Australia East" and "australiaeast"
    if ($loc1 -eq $loc2)
    {
        return $true
    }
    else
    {
        # See if $loc1 is Location and $loc2 is DisplayName
        $loc = $locations | Where-Object { $_.Location -eq $loc1 -and $_.DisplayName -eq $loc2 }
        if ($loc -ne $null)
        {
            return $true
        }

        # See if $loc1 is DisplayName and $loc2 is Location
        $loc = $locations | Where-Object { $_.DisplayName -eq $loc1 -and $_.Location -eq $loc2 }
        if ($loc -ne $null)
        {
            return $true
        }

        return $false
    }
}


function Show-AzureRmConfigurationDrift
{
    param (
        $resourceGroupName,
        $templateFile,
        $templateParametersFile
    )

    $templateResources = ExpandTemplate -resourceGroupName $resourceGroupName -templateFile $templateFile -templateParametersFile $templateParametersFile
    $rgResources = GetResourcesInRG -resourceGroupName $resourceGroupName
    CompareResourceLists -templateResources $templateResources -rgResources $rgResources

}

Show-AzureRmConfigurationDrift -resourceGroupName "driftn2" -templateFile C:\users\tomholl\Downloads\web-azuredeploy.json -templateParametersFile C:\users\tomholl\Downloads\web-azuredeploy.parameters.json
