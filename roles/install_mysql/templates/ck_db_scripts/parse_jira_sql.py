#!/usr/bin/python2.7
import os
from jira import JIRA
import re
sql_path_file='./sql_path.txt'
db_schema_file='db_schema.txt'

# prompt for jira credentials 
def get_jiracredential():
    cred = {}
    cred['user'] = raw_input("Username: ")
    cred['passwd'] = getpass.getpass("Password: ")
    return cred

def get_issues(ticket):
  sqlIssues = []

  login = get_jiracredential()
  jira = JIRA('https://jira.creditkarma.com', basic_auth=(login['user'], login['passwd']))                                                                                                                                                        if ticket == 'new':
    issues = jira.search_issues('project = "Build & Release" AND issuetype = "Microservice SQL" and status not in ("executed","declined")  ORDER BY issuekey DESC',maxResults=1);
  else:
    issues = [jira.issue(ticket)]

  for sqlIssue in issues:
    sqlIssues.append(sqlIssue)
  return sqlIssues

def get_fields(issue):
    # DB schema pefix
    return issue.fields.customfield_16600

def get_description(issue):
  description = issue.fields.description
  sqlDesc = description.split('/sql/')
  return sqlDesc

def create_dir(sqlDir):
  if not os.path.exists(sqlDir):
    os.makedirs(sqlDir)

def clear_sql_path_file():
  open(sql_path_file,'w').close()

def download_sql(issue,codeLink,sqlText):
      sqlLink = 'sql/' + codeLink
      listLink = sqlLink.split('/')[:-1]
      sqlDir=str(issue) + '/' + "/".join([str(x) for x in listLink])
      sqlFile=codeLink.split('/')[-1]
      create_dir(sqlDir)
      dbPath = str(issue) + '/' + db_schema_file
      sqlPath = sqlDir + '/' + sqlFile
      with open(sql_path_file,'a') as f1:
        f1.write(sqlPath + '\n')
      with open(sqlPath, 'w') as f2:
        f2.write(sqlText.strip('\n'))
      dbSchema = get_fields(issue)
      if dbSchema:
        with open(dbPath, 'w') as f3:
          f3.write(dbSchema)
      else:
        with open(dbPath, 'w') as f3:
          f3.write("")

def get_sql(issue,link=None):
  clear_sql_path_file()
  sqlDesc = get_description(issue)
  for x in range(1, len(sqlDesc)):
      request = sqlDesc[x].split('{code}')

      sqlText=request[1] ## original
      #sqlText=request[0].split(']')[1].split('}')[1]

      codeLink=request[0].split(']')[0]
      sqlLink='sql/' + codeLink

      if link:
        linkCheck = re.compile(link)
        if re.match(linkCheck, sqlLink):
          download_sql(issue, codeLink, sqlText)
      else:
          download_sql(issue, codeLink, sqlText)

def main(ticket,link=None):
  try:
    issues = get_issues(ticket)
    for issue in issues:
      get_sql(issue,link)
  except BaseException as e:
    print("Check if the jira ticket exists?\nError: %s" % e)

if __name__ == '__main__':
  main('new')                         
