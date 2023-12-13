$ResourceGroup = '##RESOURCEGROUP##'
$Subscription = '##SUBSCRIPTION##'
$FunctionName = '##FUNCTIONAPP##'

$Logo = @'
   _____ _____ _____  _____  
  / ____|_   _|  __ \|  __ \ 
 | |      | | | |__) | |__) |
 | |      | | |  ___/|  ___/ 
 | |____ _| |_| |    | |     
  \_____|_____|_|    |_|     
                
'@
Write-Host $Logo

Write-Host '- Connecting to Azure'
Connect-AzAccount -Identity -Subscription $Subscription | Out-Null

Write-Host 'Checking deployment settings'
$DeploymentSettings = & az functionapp deployment source show --resource-group $ResourceGroup --name $FunctionName | ConvertFrom-Json

if (!($DeploymentSettings.isGitHubAction)) {
    Write-Host 'Creating GitHub action, follow the prompts to log into GitHub'
    $GitHubRepo = ([uri]$DeploymentSettings.repoUrl).LocalPath.TrimStart('/')
    az functionapp deployment github-actions add --repo $GitHubRepo --branch $DeploymentSettings.branch --resource-group $ResourceGroup --name $FunctionName --login-with-github
}

$DeploymentSettings = & az functionapp deployment source show --resource-group $ResourceGroup --name $FunctionName | ConvertFrom-Json
if ($DeploymentSettings.isGitHubAction) {
    $cipp = Get-AzFunctionApp -ResourceGroupName $ResourceGroup
    $cipp.ApplicationSettings['WEBSITE_RUN_FROM_PACKAGE'] = 1
    $cipp | Update-AzFunctionAppSetting -AppSetting $cipp.ApplicationSettings

    Write-Host "GitHub action created and project set to run from package, navigate to $($DeploymentSettings.repoUrl)/actions and run the 'Build and deploy Powershell project to Azure Function App'"
}
else {
    Write-Host 'GitHub action not set up for deployment, try running the script again.'
}
