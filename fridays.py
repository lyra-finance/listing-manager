from datetime import date, timedelta

def main():
  print('Welcome to the Friday finder')
  print()
  year = int(input('Enter a year: '))
  print()
  print('The Fridays in', year, 'are:')
  for d in allFridays(year):
    print(d)

def allFridays(year):
  print('entered allFridays');
  d = date(year, 1, 1) # January 1st
  d += timedelta(days = 6)  # First Sunday
  print (d)
  print (year)
  while d.year == year:
    yield d
    d += timedelta(days = 7)

if __name__ == '__main__':
  main()