import xmltodict
import json

def convert_to_json(collection):
    with open(collection) as xml_file:
        data_dict = xmltodict.parse(xml_file.read())
        json_data = json.dumps(data_dict)

        with open("data.json", "w") as json_file:
            json_file.write(json_data)