After browsing through the source code, we found that there are few strange points about WEBSITE_DEPLOYMENT_ID naming.

<img width="948" height="683" alt="image (5)" src="https://github.com/user-attachments/assets/345dc72e-ba87-4bb4-9d7c-aeae971f9354" />
<img width="971" height="885" alt="image (6)" src="https://github.com/user-attachments/assets/330ffed4-24e4-494c-8ed0-2efc13301d1a" />

Based on these two photos, 
some code shows the naming rule must be the same between key vault and function app, but others not and only need the name before "-" because you use "split" function and get the first element. 
Therefore, it's very weird. So I would like to know if you can modify or clarify why you choose to design code like this, or you can make the "split" function part consistent. For example, in invoke-execListAppId.ps1 file, 
keyvault name is "website-deployment-id split '-' [0]", while in invoke-execSAMsetup.ps1 file, the keyvault name should be "website-deployment-id split '-' [0]" but so far it is not. 
Thanks!!
