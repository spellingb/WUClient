Function Get-WUClientSetting {
    [CmdletBinding()]
    Param
    (
        # Name of computer to connect to. Can be a collection of computers.
        [Parameter(ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true, 
                   Position=0)]
        [ValidateNotNullOrEmpty()]
        [Alias("Computer")] 
        [string[]]$ComputerName=$env:COMPUTERNAME,

        [switch]$Detailed
    )

    Begin
    {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent()
		$admincheck = (New-Object Security.Principal.WindowsPrincipal $me).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)

		if(!$admincheck)
		{
            Write-Warning ( "{0}: Please Close Powershell and run as Administrator." -f $me.Name	)
            exit
		} #End If !$admincheck        
        $AUValues = @(
            'AUOptions',
            'ScheduledInstallDay',
            'ScheduledInstallTime',
            'NoAutoUpdate',
            'DetectionFrequency',
            'DetectionFrequencyEnabled',
            'AlwaysAutoRebootAtScheduledTime',
            'AlwaysAutoRebootAtScheduledTimeMinutes'
            )

        $AllParams = @(
            'ComputerName',
            'TimeZone'
            'WUServer',
            'WUStatusServer',
            'AUOptions',
            'ScheduledInstallDay',
            'ScheduledInstallTime',
            'NoAutoUpdate',
            'DetectionFrequency',
            'DetectionFrequencyEnabled',
            'AlwaysAutoRebootAtScheduledTime',
            'AlwaysAutoRebootAtScheduledTimeMinutes'
        )


        $props= @{}
        $AllParams | foreach {$props.Add( $_ ,'')}

        
        $SelectParams = @(
            'ComputerName',
            'TimeZone'
            'WUServer',
            'AUOptions',
            'ScheduledInstallDay',
            'ScheduledInstallTime'
        )

        $results = New-Object System.Collections.ArrayList

        Function Get-WUKey($RegKey,[ValidateSet('WU','AU')]$SubKey,$KeyName){
            $WUKey = Switch($Subkey)
            {            
                "WU" 
                {
                    $regkey.OpenSubKey('Software\Policies\Microsoft\Windows\WindowsUpdate',$True)
                }
                "AU"
                {
                    $regkey.OpenSubKey('Software\Policies\Microsoft\Windows\WindowsUpdate\AU',$True)
                }
                
            }
            $keyval = $wukey.getvalue($KeyName)
            $WUKey.close()
            If($null -eq $keyval){"Undefined"}else{$keyval}
        }#Get-WUKey

        Function Convert-RegValue($AU,$Day,$time){
            switch($true)
            {
                $PSBoundParameters.ContainsKey('au')
                {
                    switch($au)
                    {
                        1 {"NoCheck"}
                        2 {"CheckOnly"}
                        3 {"DownloadOnly"}
                        4 {"Install"}
                        Default {"Undefined"}
                    }
                    break
                }
                $PSBoundParameters.ContainsKey('day')
                {
                    switch($day)
                    {
                        0 {'Everyday'}
                        1 {'Sunday'}
                        2 {'Monday'}
                        3 {'Tuesday'}
                        4 {'Wednesday'}
                        5 {'Thursday'}
                        6 {'Friday'}
                        7 {'Saturday'}
                    }
                    break
                }
                $PSBoundParameters.ContainsKey('time')
                {
                    try
                    {
                        get-date -Hour $time -Minute 0 -Format t -ErrorAction Stop
                    } Catch {"Undefined"}
                }
            }

        }#Convert-RegValue

    }#Begin

    Process
    {
        
        $ErrorActionPreference = 'stop'
        foreach($Computer in $ComputerName)
        {
            try
            {
                $remoteregistrystatus = (Get-Service -Name RemoteRegistry -ComputerName "$computer" -ErrorAction Stop).status
                if($remoteregistrystatus -ne 'started')
                {
                    Set-Service -Name RemoteRegistry -ComputerName $computer -StartupType Manual -ErrorAction Stop
                    Set-Service -Name RemoteRegistry -ComputerName $Computer -Status Running -ErrorAction Stop
                }
                $Reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $computer)
                $temp = $Reg.OpenSubKey('Software\Policies\Microsoft\Windows',$True)

                If (-NOT ($temp.GetSubKeyNames() -contains 'WindowsUpdate')) 
                {
                    #Build the required registry keys
                    $temp.CreateSubKey('WindowsUpdate\AU') | Out-Null
                }
                
            }
            catch [Microsoft.PowerShell.Commands.ServiceCommandException]
            {
                Write-Warning ( "{0}: Unable to Start {1} on Computer.`nReason:`n`t{2}" -f $Computer,$_.exception.servicename,$_.exception)
            }
            catch
            {
                write-warning ( "{0}: Unable to communicate to establish Remote Registy Connection." -f $Computer) 
                
                break
            }
            try {
                $timezone = (Get-WmiObject -Class win32_timezone -ComputerName "$computer").caption
            } catch {
                $timezone = 'unavailable'
            }

            $compresults = New-Object psobject -Property $props

            #$compresults = "" | Select-Object $AllParams
            $compresults.ComputerName = $Computer
            $compresults.TimeZone = (Get-WmiObject -Class win32_timezone -ComputerName "$computer").caption
            
            Foreach($WUValue in @('WUServer','WUStatusServer'))
            {
                $compresults.$wuvalue = Get-WUKey -RegKey $Reg -SubKey WU -KeyName $WUValue
            }

            foreach($AUValue in $AUValues)
            {
                $compresults.$AUValue =  Get-WUKey -RegKey $Reg -SubKey AU -KeyName $AUValue
            }
            
            $compresults.AUOptions = Convert-RegValue -AU $compresults.AUOptions
            $compresults.ScheduledInstallDay = Convert-RegValue -Day $compresults.ScheduledInstallDay
            $compresults.ScheduledInstallTime = Convert-RegValue -time $compresults.ScheduledInstallTime
            $results.Add($compresults) | Out-Null

        }#Foreach Computer
    }#Process
    End
    {
        if($Detailed){
            $results
        } else {
            $results | Select-Object $SelectParams
        }
    }
}