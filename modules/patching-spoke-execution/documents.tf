# =============================================================================
# 1. PRE-CHECK DOCUMENT (Updated for Internet Connectivity)
# =============================================================================
resource "aws_ssm_document" "pre_check" {
  name            = "CCS-Patching-PreCheck"
  document_type   = "Command"
  document_format = "YAML"
  content = <<DOC
schemaVersion: '2.2'
description: "Pre-Check: Verify Disk Space & Internet Connectivity"
mainSteps:
  # -------------------- LINUX CHECK --------------------
  - action: aws:runShellScript
    name: checkDiskLinux
    precondition:
      StringEquals:
        - platformType
        - Linux
    inputs:
      runCommand:
        - |
          #!/bin/bash
          df -h / | awk 'NR==2 {print $5}' | sed 's/%//' | awk '{if($1 > 90) exit 1; else exit 0}'
          if [ $? -eq 0 ]; then echo "Linux Pre-Check Passed: Disk Space OK"; else echo "Linux Pre-Check Failed: Disk Full"; exit 1; fi

  # -------------------- WINDOWS CHECK --------------------
  - action: aws:runPowerShellScript
    name: checkWindows
    precondition:
      StringEquals:
        - platformType
        - Windows
    inputs:
      runCommand:
        - |
          # 1. Disk Space Check
          $drive = Get-PSDrive C
          $free = $drive.Free / $drive.Used
          if ($free -lt 0.1) { 
            Write-Error "Windows Pre-Check Failed: Disk Full (<10% Free)"
            exit 1 
          }
          Write-Output "Disk Space: OK"

          # 2. Connectivity Check (Confirms NAT/Gateway is working)
          # We use ntservicepack.microsoft.com as confirmed in your testing
          try {
            $r = Invoke-WebRequest -Uri "http://ntservicepack.microsoft.com" -UseBasicParsing -TimeoutSec 5 -Method Head
            Write-Output "Windows Pre-Check Passed: Internet Reachable"
          } catch {
            Write-Error "Windows Pre-Check Failed: Cannot reach Microsoft Update. Check NAT/TGW."
            exit 1
          }
DOC
}

# =============================================================================
# 2. POST-CHECK DOCUMENT (Unchanged)
# =============================================================================
resource "aws_ssm_document" "post_check" {
  name            = "CCS-Patching-PostCheck"
  document_type   = "Command"
  document_format = "YAML"
  content = <<DOC
schemaVersion: '2.2'
description: "Post-Check: Verify Critical Services"
mainSteps:
  - action: aws:runShellScript
    name: checkServiceLinux
    precondition:
      StringEquals:
        - platformType
        - Linux
    inputs:
      runCommand:
        - |
          systemctl is-active amazon-ssm-agent
          if [ $? -eq 0 ]; then echo "Linux Post-Check Passed"; else echo "Linux Post-Check Failed"; exit 1; fi

  - action: aws:runPowerShellScript
    name: checkServiceWindows
    precondition:
      StringEquals:
        - platformType
        - Windows
    inputs:
      runCommand:
        - |
          if ((Get-Service AmazonSSMAgent).Status -eq 'Running') { 
             Write-Output "Windows Post-Check Passed"
          } else {
             Write-Error "Windows Post-Check Failed"
             exit 1
          }
DOC
}

# =============================================================================
# 3. ORCHESTRATOR DOCUMENT (Removed WSUS Steps)
# =============================================================================
resource "aws_ssm_document" "orchestrator" {
  name            = "CCS-Orchestrated-Patching-With-Retries"
  document_type   = "Automation"
  document_format = "YAML"
  content = <<DOC
description: "Orchestrated Patching (Direct Internet - Aggressive Reset)"
schemaVersion: "0.3"
assumeRole: "{{ AutomationAssumeRole }}"
parameters:
  InstanceId:
    type: String
  AutomationAssumeRole:
    type: String
  Operation:
    type: String
    default: "Install"

mainSteps:
  # =========================================================
  # 1. DETECT OS (Branching Logic)
  # =========================================================
  - name: CheckOS
    action: aws:executeScript
    inputs:
      Runtime: python3.11
      Handler: script_handler
      InputPayload:
        InstanceId: "{{InstanceId}}"
      Script: |
        import boto3
        def script_handler(events, context):
            ec2 = boto3.client('ec2')
            try:
                d = ec2.describe_instances(InstanceIds=[events['InstanceId']])
                p = d['Reservations'][0]['Instances'][0].get('Platform', 'Linux')
                return {'OS': 'Windows' if p == 'windows' else 'Linux'}
            except: return {'OS': 'Linux'}
    outputs:
      - Name: OS
        Selector: $.Payload.OS
        Type: String

  # 2. CHECK OPT-OUT STATUS
  - name: CheckOptOutStatus
    action: aws:executeScript
    onFailure: step:SendFailureNotification
    inputs:
      Runtime: python3.11
      Handler: script_handler
      Script: |
        import boto3
        import time
        import logging
        logger = logging.getLogger()
        logger.setLevel(logging.INFO)
        def script_handler(events, context):
            try:
                dynamodb = boto3.resource('dynamodb')
                # Matches your screenshot/setup
                table = dynamodb.Table('CCS-Patching-OptOut-State') 
                account_id = boto3.client('sts').get_caller_identity().get('Account')
                response = table.get_item(Key={'AccountId': account_id})
                if 'Item' in response:
                    expiry = int(response['Item'].get('OptOutExpiry', 0))
                    if int(time.time()) < expiry:
                        return {'opted_out': True}
                return {'opted_out': False}
            except Exception as e:
                logger.error(f"OptOut Check Failed: {str(e)}")
                raise e
    outputs:
      - Name: OptedOut
        Selector: $.Payload.opted_out
        Type: Boolean

  # 3. DECISION BRANCH
  - name: VerifyOptOut
    action: aws:branch
    inputs:
      Choices:
      - NextStep: EndExecution
        Variable: "{{CheckOptOutStatus.OptedOut}}"
        BooleanEquals: true
      Default: EnterASGStandby

  # 4. ASG SAFETY
  - name: EnterASGStandby
    action: aws:executeScript
    onFailure: step:SendFailureNotification
    inputs:
      Runtime: python3.11
      Handler: script_handler
      InputPayload:
        InstanceId: "{{InstanceId}}"
      Script: |
        import boto3
        import logging
        logger = logging.getLogger()
        logger.setLevel(logging.INFO)
        def script_handler(events, context):
            ec2_id = events['InstanceId']
            try:
                asg = boto3.client('autoscaling')
                resp = asg.describe_auto_scaling_instances(InstanceIds=[ec2_id])
                if resp['AutoScalingInstances']:
                    grp = resp['AutoScalingInstances'][0]
                    if grp['LifecycleState'] == 'InService':
                        asg.enter_standby(InstanceIds=[ec2_id], AutoScalingGroupName=grp['AutoScalingGroupName'], ShouldDecrementDesiredCapacity=True)
            except Exception as e:
                logger.error(f"ASG Standby Failed: {str(e)}")

  # 5. DISABLE ALARMS
  - name: DisableAlarms
    action: aws:executeAutomation
    onFailure: Continue 
    inputs:
      DocumentName: "AWS-ConfigureCloudWatchOnEC2Instance"
      RuntimeParameters:
        InstanceId: "{{InstanceId}}"
        status: "Disabled"

  # 6. CREATE SNAPSHOTS
  - name: CreatePrePatchSnapshots
    action: aws:executeScript
    timeoutSeconds: 3600
    onFailure: step:SendFailureNotification
    inputs:
      Runtime: python3.11
      Handler: script_handler
      InputPayload:
        InstanceId: "{{InstanceId}}"
      Script: |
        import boto3
        import datetime
        import logging
        logger = logging.getLogger()
        logger.setLevel(logging.INFO)
        def script_handler(events, context):
            instance_id = events['InstanceId']
            ec2 = boto3.client('ec2')
            try:
                desc = ec2.describe_instances(InstanceIds=[instance_id])
                volumes = [m['Ebs']['VolumeId'] for m in desc['Reservations'][0]['Instances'][0].get('BlockDeviceMappings', []) if 'Ebs' in m]
                if not volumes: return {'snapshots': []}
                
                created = []
                ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                for vid in volumes:
                    resp = ec2.create_snapshot(VolumeId=vid, Description=f"PrePatch {instance_id} {ts}")
                    ec2.create_tags(Resources=[resp['SnapshotId']], Tags=[{'Key':'Purpose','Value':'PrePatch'}])
                    created.append(resp['SnapshotId'])
                
                waiter = ec2.get_waiter('snapshot_completed')
                waiter.wait(SnapshotIds=created, WaiterConfig={'Delay': 15, 'MaxAttempts': 120})
                return {'snapshots': created}
            except Exception as e:
                logger.error(str(e))
                raise e

  # 7. PRE-CHECK
  - name: PreCheck
    action: aws:runCommand
    maxAttempts: 3
    timeoutSeconds: 300
    onFailure: step:SendFailureNotification
    inputs:
      DocumentName: "${aws_ssm_document.pre_check.name}"
      InstanceIds: ["{{InstanceId}}"]

  # =========================================================
  # 8. BRANCHING: SKIP RESET ON LINUX
  # =========================================================
  - name: BranchReset
    action: aws:branch
    inputs:
      Choices:
      - NextStep: ResetWindowsUpdate
        Variable: "{{CheckOS.OS}}"
        StringEquals: "Windows"
      Default: PatchInstance

  # =========================================================
  # 9. AGGRESSIVE RESET (Windows Only)
  # =========================================================
  - name: ResetWindowsUpdate
    action: aws:runCommand
    maxAttempts: 3
    inputs:
      DocumentName: "AWS-RunPowerShellScript"
      InstanceIds: ["{{InstanceId}}"]
      Parameters:
        commands:
          - |
            $ErrorActionPreference = "SilentlyContinue"
            Write-Output "Step 1: Stopping Windows Update Services..."
            Stop-Service -Name wuauserv -Force
            Stop-Service -Name cryptSvc -Force
            Stop-Service -Name bits -Force
            Stop-Service -Name msiserver -Force

            Write-Output "Step 2: Clearing SoftwareDistribution Cache (Fixes 0x80072EFE)..."
            Rename-Item -Path "C:\Windows\SoftwareDistribution" -NewName "C:\Windows\SoftwareDistribution.old" -Force
            Rename-Item -Path "C:\Windows\System32\catroot2" -NewName "C:\Windows\System32\catroot2.old" -Force

            Write-Output "Step 3: Removing WSUS Registry Keys..."
            $RegPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            Remove-ItemProperty -Path $RegPath -Name WUServer 
            Remove-ItemProperty -Path $RegPath -Name WUStatusServer
            if (Test-Path "$RegPath\AU") {
               Set-ItemProperty -Path "$RegPath\AU" -Name UseWUServer -Value 0
            }

            Write-Output "Step 4: Resetting Network Proxy..."
            netsh winhttp reset proxy

            Write-Output "Step 5: Restarting Services..."
            Start-Service -Name wuauserv
            Start-Service -Name bits
            
            Write-Output "Waiting 30s for service initialization..."
            Start-Sleep -Seconds 30
            Write-Output "SUCCESS: Windows Update Reset Complete."
    nextStep: PatchInstance

  # 10. APPLY PATCHES
  - name: PatchInstance
    action: aws:runCommand
    maxAttempts: 3
    timeoutSeconds: 7200
    onFailure: step:SendFailureNotification
    inputs:
      DocumentName: "AWS-RunPatchBaseline"
      InstanceIds: ["{{InstanceId}}"]
      Parameters:
        Operation: "{{Operation}}"

  # 11. POST-CHECK
  - name: PostCheck
    action: aws:runCommand
    maxAttempts: 3
    timeoutSeconds: 300
    onFailure: step:SendFailureNotification 
    inputs:
      DocumentName: "${aws_ssm_document.post_check.name}"
      InstanceIds: ["{{InstanceId}}"]

  # 12. ENABLE ALARMS
  - name: EnableAlarms
    action: aws:executeAutomation
    inputs:
      DocumentName: "AWS-ConfigureCloudWatchOnEC2Instance"
      RuntimeParameters:
        InstanceId: "{{InstanceId}}"
        status: "Enabled"

  # 13. EXIT STANDBY
  - name: ExitASGStandby
    action: aws:executeScript
    inputs:
      Runtime: python3.11
      Handler: script_handler
      InputPayload:
        InstanceId: "{{InstanceId}}"
      Script: |
        import boto3
        def script_handler(events, context):
            try:
                ec2 = events['InstanceId']
                asg = boto3.client('autoscaling')
                r = asg.describe_auto_scaling_instances(InstanceIds=[ec2])
                if r['AutoScalingInstances'] and r['AutoScalingInstances'][0]['LifecycleState'] == 'Standby':
                   asg.exit_standby(InstanceIds=[ec2], AutoScalingGroupName=r['AutoScalingInstances'][0]['AutoScalingGroupName'])
            except: pass

  # 14. NOTIFY SUCCESS
  - name: NotifySuccess
    action: aws:executeScript
    inputs:
      Runtime: python3.11
      Handler: script_handler
      InputPayload:
        InstanceId: "{{InstanceId}}"
      Script: |
        import boto3
        import json
        def script_handler(events, context):
            sns = boto3.client('sns')
            topic = "${aws_sns_topic.patch_alerts.arn}"
            msg = {"default": f"Patching SUCCESS for {events['InstanceId']}"}
            sns.publish(TopicArn=topic, Message=json.dumps(msg), Subject="Patching Success", MessageStructure='json')
    isEnd: true

  # 15. FAILURE HANDLER
  - name: SendFailureNotification
    action: aws:executeScript
    inputs:
      Runtime: python3.11
      Handler: script_handler
      InputPayload:
        InstanceId: "{{InstanceId}}"
      Script: |
        import boto3
        import json
        def script_handler(events, context):
            sns = boto3.client('sns')
            topic = "${aws_sns_topic.patch_alerts.arn}"
            msg = {"default": f"Patching FAILED for {events['InstanceId']}. Check SSM Logs."}
            sns.publish(TopicArn=topic, Message=json.dumps(msg), Subject="Patching FAILED", MessageStructure='json')
    nextStep: FailExecution

  - name: FailExecution
    action: aws:executeScript
    inputs:
      Runtime: python3.11
      Handler: script_handler
      Script: "def script_handler(e, c): raise Exception('Workflow Failed')"

  - name: EndExecution
    action: aws:sleep
    inputs:
      Duration: "PT1S"
DOC
}