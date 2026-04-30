from django.core.management.base import BaseCommand
from domain.nutrition.models import Food


FOODS = [
    # name, category, kcal, protein, carb, fat, fiber, sugar
    # Cereali & Derivati
    ("Riso bianco cotto", "Cereali", 130, 2.7, 28.6, 0.3, 0.4, 0.1),
    ("Riso integrale cotto", "Cereali", 123, 2.7, 25.8, 1.0, 1.8, 0.3),
    ("Pasta cotta", "Cereali", 158, 5.8, 30.9, 0.9, 1.8, 0.5),
    ("Pasta integrale cotta", "Cereali", 149, 5.5, 28.2, 1.1, 3.5, 0.6),
    ("Pane bianco", "Cereali", 265, 8.9, 53.4, 1.4, 2.7, 4.1),
    ("Pane integrale", "Cereali", 247, 9.0, 45.5, 2.5, 6.0, 3.5),
    ("Avena fiocchi", "Cereali", 389, 16.9, 66.3, 6.9, 10.6, 1.1),
    ("Farro cotto", "Cereali", 133, 5.5, 26.8, 0.7, 3.5, 0.3),
    ("Orzo cotto", "Cereali", 123, 2.3, 28.2, 0.4, 6.0, 0.3),
    ("Quinoa cotta", "Cereali", 120, 4.4, 21.3, 1.9, 2.8, 0.9),
    ("Farina 00", "Cereali", 355, 11.5, 74.0, 1.4, 2.7, 0.5),
    ("Polenta cotta", "Cereali", 80, 2.0, 18.0, 0.3, 1.4, 0.2),
    ("Muesli", "Cereali", 367, 8.5, 65.0, 8.0, 7.0, 26.0),
    ("Crackers", "Cereali", 432, 9.5, 71.0, 12.0, 3.5, 3.0),
    ("Fette biscottate", "Cereali", 397, 10.0, 79.5, 4.5, 3.0, 8.0),

    # Carni
    ("Pollo petto senza pelle", "Carne", 110, 23.1, 0.0, 1.8, 0.0, 0.0),
    ("Pollo coscia senza pelle", "Carne", 165, 18.5, 0.0, 9.7, 0.0, 0.0),
    ("Tacchino petto", "Carne", 104, 21.9, 0.0, 1.4, 0.0, 0.0),
    ("Manzo macinato magro", "Carne", 200, 21.0, 0.0, 12.5, 0.0, 0.0),
    ("Manzo fettina", "Carne", 156, 26.3, 0.0, 5.7, 0.0, 0.0),
    ("Vitello scaloppina", "Carne", 127, 23.0, 0.0, 3.5, 0.0, 0.0),
    ("Maiale lonza", "Carne", 182, 21.0, 0.0, 10.6, 0.0, 0.0),
    ("Prosciutto crudo", "Carne", 268, 25.5, 0.0, 18.0, 0.0, 0.3),
    ("Prosciutto cotto", "Carne", 136, 19.0, 1.0, 6.3, 0.0, 0.8),
    ("Bresaola", "Carne", 151, 32.4, 0.0, 2.3, 0.0, 0.0),
    ("Fesa di tacchino", "Carne", 107, 24.0, 0.0, 1.0, 0.0, 0.0),
    ("Agnello coscio", "Carne", 206, 22.0, 0.0, 13.0, 0.0, 0.0),

    # Pesce & Frutti di mare
    ("Salmone fresco", "Pesce", 208, 20.0, 0.0, 13.4, 0.0, 0.0),
    ("Tonno in scatola (al naturale)", "Pesce", 103, 23.0, 0.0, 0.8, 0.0, 0.0),
    ("Merluzzo", "Pesce", 79, 18.3, 0.0, 0.6, 0.0, 0.0),
    ("Orata", "Pesce", 96, 20.3, 0.0, 1.8, 0.0, 0.0),
    ("Spigola (branzino)", "Pesce", 97, 18.6, 0.0, 2.5, 0.0, 0.0),
    ("Sgombro", "Pesce", 205, 19.0, 0.0, 13.9, 0.0, 0.0),
    ("Gamberetti", "Pesce", 99, 20.9, 0.9, 1.1, 0.0, 0.0),
    ("Calamari", "Pesce", 92, 15.6, 3.1, 1.4, 0.0, 0.0),
    ("Acciughe sott'olio", "Pesce", 210, 28.9, 0.0, 10.5, 0.0, 0.0),
    ("Sarda", "Pesce", 159, 20.6, 0.0, 8.4, 0.0, 0.0),

    # Uova & Latticini
    ("Uovo intero", "Uova & Latticini", 143, 12.6, 0.7, 9.5, 0.0, 0.4),
    ("Albume d'uovo", "Uova & Latticini", 52, 11.0, 0.7, 0.2, 0.0, 0.4),
    ("Latte intero", "Uova & Latticini", 61, 3.3, 4.8, 3.3, 0.0, 4.8),
    ("Latte scremato", "Uova & Latticini", 35, 3.5, 5.0, 0.1, 0.0, 5.0),
    ("Yogurt greco 0%", "Uova & Latticini", 57, 10.0, 3.6, 0.4, 0.0, 3.6),
    ("Yogurt greco intero", "Uova & Latticini", 97, 9.0, 3.6, 5.0, 0.0, 3.6),
    ("Ricotta (vaccina)", "Uova & Latticini", 146, 11.3, 3.0, 10.0, 0.0, 3.0),
    ("Mozzarella", "Uova & Latticini", 253, 18.0, 2.7, 19.0, 0.0, 0.5),
    ("Parmigiano reggiano", "Uova & Latticini", 392, 33.0, 0.0, 28.4, 0.0, 0.0),
    ("Grana padano", "Uova & Latticini", 384, 33.0, 0.0, 28.0, 0.0, 0.0),
    ("Fiocchi di latte", "Uova & Latticini", 98, 12.5, 2.5, 4.3, 0.0, 2.5),
    ("Formaggino/Philadelphia", "Uova & Latticini", 258, 6.2, 4.1, 23.5, 0.0, 3.0),
    ("Pecorino", "Uova & Latticini", 387, 25.8, 0.0, 31.0, 0.0, 0.0),
    ("Burro", "Uova & Latticini", 717, 0.9, 0.1, 81.0, 0.0, 0.1),

    # Legumi
    ("Lenticchie cotte", "Legumi", 116, 9.0, 20.1, 0.4, 7.9, 1.8),
    ("Ceci cotti", "Legumi", 164, 8.9, 27.4, 2.6, 7.6, 4.8),
    ("Fagioli borlotti cotti", "Legumi", 132, 8.7, 23.8, 0.5, 9.7, 3.1),
    ("Fagioli cannellini cotti", "Legumi", 124, 8.5, 22.0, 0.5, 8.5, 0.4),
    ("Piselli cotti", "Legumi", 84, 5.4, 15.6, 0.4, 5.1, 5.9),
    ("Edamame", "Legumi", 122, 11.9, 8.9, 5.2, 5.2, 2.2),
    ("Tofu", "Legumi", 76, 8.1, 1.9, 4.2, 0.3, 0.5),

    # Verdure
    ("Spinaci crudi", "Verdure", 23, 2.9, 3.6, 0.4, 2.2, 0.4),
    ("Broccoli", "Verdure", 34, 2.8, 6.6, 0.4, 2.6, 1.7),
    ("Insalata mista", "Verdure", 20, 1.4, 3.3, 0.3, 1.5, 1.5),
    ("Pomodori", "Verdure", 18, 0.9, 3.9, 0.2, 1.2, 2.6),
    ("Carote", "Verdure", 41, 0.9, 9.6, 0.2, 2.8, 4.7),
    ("Zucchine", "Verdure", 17, 1.2, 3.1, 0.3, 1.0, 2.5),
    ("Peperoni", "Verdure", 31, 1.0, 6.0, 0.3, 2.1, 4.2),
    ("Cetrioli", "Verdure", 16, 0.7, 3.6, 0.1, 0.5, 1.7),
    ("Cavolfiore", "Verdure", 25, 1.9, 5.0, 0.3, 2.0, 1.9),
    ("Asparagi", "Verdure", 20, 2.2, 3.9, 0.1, 2.1, 1.9),
    ("Funghi champignon", "Verdure", 22, 3.1, 3.3, 0.3, 1.0, 1.7),
    ("Cipolle", "Verdure", 40, 1.1, 9.3, 0.1, 1.7, 4.2),
    ("Aglio", "Verdure", 149, 6.4, 33.1, 0.5, 2.1, 1.0),
    ("Pomodori pelati", "Verdure", 24, 1.1, 4.8, 0.2, 1.3, 3.5),
    ("Cavolo cappuccio", "Verdure", 25, 1.3, 5.8, 0.1, 2.5, 3.2),

    # Frutta
    ("Mela", "Frutta", 52, 0.3, 13.8, 0.2, 2.4, 10.4),
    ("Banana", "Frutta", 89, 1.1, 22.8, 0.3, 2.6, 12.2),
    ("Arancia", "Frutta", 47, 0.9, 11.8, 0.1, 2.4, 9.4),
    ("Fragole", "Frutta", 32, 0.7, 7.7, 0.3, 2.0, 4.9),
    ("Mirtilli", "Frutta", 57, 0.7, 14.5, 0.3, 2.4, 10.0),
    ("Kiwi", "Frutta", 61, 1.1, 14.7, 0.5, 3.0, 9.0),
    ("Pera", "Frutta", 57, 0.4, 15.2, 0.1, 3.1, 9.8),
    ("Uva", "Frutta", 67, 0.6, 17.2, 0.4, 0.9, 16.3),
    ("Avocado", "Frutta", 160, 2.0, 8.5, 14.7, 6.7, 0.7),
    ("Limone", "Frutta", 29, 1.1, 9.3, 0.3, 2.8, 2.5),

    # Grassi & Condimenti
    ("Olio d'oliva extravergine", "Grassi", 884, 0.0, 0.0, 100.0, 0.0, 0.0),
    ("Olio di semi di girasole", "Grassi", 884, 0.0, 0.0, 100.0, 0.0, 0.0),
    ("Mandorle", "Frutta secca", 576, 21.2, 21.7, 49.4, 12.5, 4.4),
    ("Noci", "Frutta secca", 654, 15.2, 13.7, 65.2, 6.7, 2.6),
    ("Anacardi", "Frutta secca", 553, 18.2, 30.2, 43.8, 3.3, 5.9),
    ("Arachidi", "Frutta secca", 567, 25.8, 16.1, 49.2, 8.5, 4.7),
    ("Semi di chia", "Frutta secca", 486, 16.5, 42.1, 30.7, 34.4, 0.0),
    ("Semi di lino", "Frutta secca", 534, 18.3, 28.9, 42.2, 27.3, 1.5),

    # Proteine in polvere & Integratori
    ("Whey protein (polvere)", "Integratori", 370, 75.0, 10.0, 5.0, 0.0, 4.0),
    ("Caseina (polvere)", "Integratori", 363, 78.0, 5.0, 4.0, 0.0, 3.0),
    ("Proteine vegetali soia", "Integratori", 336, 81.0, 2.0, 5.0, 0.0, 0.0),

    # Dolci & Altro
    ("Miele", "Dolci", 304, 0.3, 82.4, 0.0, 0.2, 82.1),
    ("Cioccolato fondente 70%", "Dolci", 598, 7.8, 45.9, 42.6, 10.9, 24.2),
    ("Marmellata", "Dolci", 278, 0.5, 69.5, 0.1, 1.5, 55.0),
    ("Nutella", "Dolci", 539, 6.3, 57.5, 30.9, 3.4, 56.3),
]


class Command(BaseCommand):
    help = 'Popola il database con alimenti comuni (macros per 100g)'

    def handle(self, *args, **kwargs):
        created = 0
        for row in FOODS:
            name, category, kcal, protein, carb, fat, fiber, sugar = row
            _, made = Food.objects.get_or_create(
                name=name,
                defaults=dict(
                    category=category,
                    kcal_per_100g=kcal,
                    protein_per_100g=protein,
                    carb_per_100g=carb,
                    fat_per_100g=fat,
                    fiber_per_100g=fiber,
                    sugar_per_100g=sugar,
                )
            )
            if made:
                created += 1

        self.stdout.write(self.style.SUCCESS(f'Alimenti creati: {created} / {len(FOODS)}'))
