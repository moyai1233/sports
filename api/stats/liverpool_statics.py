import requests
import json

url = "https://v3.football.api-sports.io/teams/statistics"

headers = {
    "x-apisports-key": "d4886da2e500ffd92f198ce1783ec217"
}

params = {
    "league": 39,
    "season": 2024,
    "team": 40
}

response = requests.get(url, headers=headers, params=params)
data = response.json()

team_stats = data["response"]

print(team_stats["team"]["name"])
print(team_stats["fixtures"]["played"]["total"])

with open("liverpool_stats.json", "w", encoding="utf-8") as file:
    json.dump(team_stats, file, ensure_ascii=False, indent=4)