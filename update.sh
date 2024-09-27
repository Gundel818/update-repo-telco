#!/bin/bash

set -e

timestamp() {
  date +"[%Y-%m-%d %H:%M:%S]"
}

# Étape 0 : Init
echo "$(timestamp) Démarrage du script"

cd /home/ubuntu/telco-tools || { echo "$(timestamp) Erreur : Impossible de se rendre dans le répertoire /home/ubuntu/telco-tools"; exit 1; }

# Étape 1 : Récup ID et date de dernière modification depuis l'API ANFR
dataset_id="observatoire_2g_3g_4g"
response=$(curl -s "https://data.anfr.fr/d4c/api/datasets/2.0/DATASETID/id=$dataset_id")
resource_id=$(echo "$response" | jq -r '.result.resources[] | select(.format == "CSV") | .id')
last_modified=$(echo "$response" | jq -r '.result.resources[] | select(.format == "CSV") | .last_modified')

if [ -z "$resource_id" ] || [ -z "$last_modified" ]; then
    echo "$(timestamp) Erreur : Aucun ID ou date de dernière modification trouvé pour le format CSV."
    exit 1
fi

echo "$(timestamp) ID CSV récupéré : $resource_id"
echo "$(timestamp) Date de dernière modification : $last_modified"

# Formatage de la date pour l'intégrer dans le nom de fichier
last_modified_date=$(date -d "$last_modified" +"%Y%m%d_%H%M")

# Étape 2 : URL de téléchargement
download_url="https://data.anfr.fr/d4c/api/records/2.0/resource/format=csv&resource_id=$resource_id&use_labels_for_header=true&refine.generation=4G"

# Nom du fichier final
output_file="lib/data_4G_ANFR_$last_modified_date.csv"

# Étape 3 : Vérifier si le fichier existe déjà et est à jour
if [ -f "$output_file" ]; then
    echo "$(timestamp) Le fichier $output_file existe déjà et est à jour."
    echo "$(timestamp) Aucun téléchargement n'est nécessaire."
else
    echo "$(timestamp) Le fichier $output_file n'existe pas ou est obsolète. Téléchargement en cours..."

    curl -L -o "$output_file" "$download_url"

    if [ $? -eq 0 ]; then
        echo "$(timestamp) Téléchargement réussi dans : $output_file"
    else
        echo "$(timestamp) Erreur lors du téléchargement"
        exit 1
    fi
fi

# Étape 4 : GIT
git_output=$(git pull)

if echo "$git_output" | grep -q "Already up to date."; then
    echo "$(timestamp) Aucun changement dans le dépôt Git. Le conteneur Docker ne sera pas redémarré."
else
    echo "$(timestamp) Mises à jour trouvées dans le dépôt Git. Redémarrage du conteneur Docker..."
    sudo docker stop telcotools-ctn
    sudo docker rm telcotools-ctn
    sudo docker build -t telcotools-docker .
    sudo docker run -d --name telcotools-ctn --restart=always -p 127.0.0.1:3000:3000 telcotools-docker
fi

echo "$(timestamp) Script terminé."