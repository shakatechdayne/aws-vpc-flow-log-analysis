import boto3
import gzip
import json
import logging
import os
from StringIO import StringIO
from botocore.config import Config

config = Config(
    retries = dict(
        max_attempts = 10
    )
)

firehose = boto3.client('firehose')
ec2 = boto3.resource('ec2', config=config)

def lambda_handler(event, context):

    encodedLogsData = str(event['awslogs']['data'])
    decodedLogsData = gzip.GzipFile(fileobj = StringIO(encodedLogsData.decode('base64','strict'))).read()
    allEvents = json.loads(decodedLogsData)

    records = []

    # Cache(s)
    # netInfCache (netId -> netInfObject)
    netInfCache = {}

    # Assumes that all events are for the same VPC
    vpcObject = None

    for event in allEvents['logEvents']:
        message = str(event['message'])
        netid = getEniId(message)

        if netid is not None:

            if netid not in netInfCache:
                netInfObj = getNetInf(netid)
                netInfCache[netid] = netInfObj
            else:
                netInfObj = netInfCache[netid]

            if vpcObject is None:
                vpcObject =  ec2.Vpc(netInfObj.vpc_id)

            associated_nacl = getNaclId(netInfObj, vpcObject)

            if associated_nacl is not None:
                message = appendLogEntry(message, associated_nacl)

            sgid = getSgIds(netInfObj)

            if sgid is not None:
                message = appendLogEntry(message, sgid)


        logEvent = {
            'Data': message + "\n"
        }

        records.append(logEvent)

        if len(records) > 499:
            print("Records are greater than 499 lets batch and send to firehose %s " % len(records))
            response = firehose.put_record_batch(
                DeliveryStreamName = os.environ['DELIVERY_STREAM_NAME'],
                Records = records
            )
            print("Response from firehose put_record_batch in message process loop is: %s" % response)
            records = []

    if len(records) > 0:
        response = firehose.put_record_batch(
            DeliveryStreamName = os.environ['DELIVERY_STREAM_NAME'],
            Records = records
        )
        print("Response from firehose put_record_batch after message process loop is: %s" % response)

def getEniId(message):

    records = message.split()

    if len(records) > 0:
        return records[2]
    else:
        return None

def getSgIds(netInfObj):

    sgroups = netInfObj.groups

    if len(sgroups) > 0:
        tempsgroupids = []
        for group in sgroups:
            tempsgroupids.append(group['GroupId'])
        lstsgroupids = ",".join(tempsgroupids)
        return lstsgroupids
    else:
        return None

def appendLogEntry(message, item):

    msgitems = message.split(' ')
    msgitems.append(item)
    message = " ".join(msgitems)

    return message

def getNaclId(netInfObj, vpcObject):

    net_acls = vpcObject.network_acls.all()
    subnetId = netInfObj.subnet_id

    for acl in net_acls:
        for association in acl.associations:
            if association['SubnetId'] == subnetId:
                return acl.network_acl_id

    return None

def getNetInf(eniId):
    return ec2.NetworkInterface(eniId)
