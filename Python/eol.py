import json
import requests
import re

def find_query_keys(obj, result):
    """
    Recursively search for 'query' keys in the JSON object.
    """
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == 'query':
                result.append(v)
            else:
                find_query_keys(v, result)
    elif isinstance(obj, list):
        for item in obj:
            find_query_keys(item, result)

def main():
    # URL of the Azure workbook JSON file
    url = 'https://github.com/microsoft/Application-Insights-Workbooks/raw/refs/heads/master/Workbooks/Azure%20Advisor/AzureServiceRetirement/Azure%20Services%20Retirement.workbook'

    # Download the JSON content from the URL
    response = requests.get(url)
    data = json.loads(response.content)

    # List to store the values of 'query' keys
    query_values = []
    find_query_keys(data, query_values)

    # Output the extracted 'query' data in human-readable JSON format
    for idx, query in enumerate(query_values):
        print(f"Query {idx+1}:")
        if query.strip():  # Check if the query string is not empty
            try:
                # Remove specific escape sequences including escaped quotes
                cleaned_query = re.sub(r'\\[rnt"]', '', query)
                print(json.dumps(json.loads(cleaned_query), indent=2, ensure_ascii=False))
            except json.JSONDecodeError as e:
                print(f"Error decoding JSON for Query {idx+1}: {e}")
        else:
            print("Empty query string, skipping...")
        print("\n")  # Add space between queries for readability

if __name__ == '__main__':
    main()
 