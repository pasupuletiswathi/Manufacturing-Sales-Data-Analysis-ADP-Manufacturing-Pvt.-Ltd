#!/usr/bin/env python
# coding: utf-8

# # Import libraries

# In[1]:


import pandas as pd
import numpy as np
import seaborn as sns
import matplotlib.pyplot as plt 
from scipy import stats


# # Load the data

# In[2]:


df=pd.read_excel(r"C:\Users\agroj\OneDrive\Documents\Desktop\ADP project\Order_wise_Data_Manufacturing.xlsx")


# In[3]:


print("Rows and columns:", df.shape)
print(df.head())                      # first 5 rows


# # Cleaning and Manipulating the data

# In[4]:


print(df.isna().sum())


# In[5]:


# Removing null values
df.dropna(inplace=True)


# In[6]:


print(df.isna().sum())


# In[7]:


#Make sure Date is a real date
df["Date"]=pd.to_datetime(df["Date"])
df


# In[8]:


# Make customer names tidy: capital letters
df["CompanyName"] = (df["CompanyName"].str.upper().str.strip())
df


# In[9]:


# adding a new column Profit margin % = profit / sales * 100
df["Margin %"] = df["Profit"] / df["Taxable Value"] * 100


# In[10]:


def get_category(name):
    name = name.upper()
    if "INSULATION" in name or "ACCOUSTIC" in name:
        return "Insulation"
    if "TDF" in name:
        return "TDF Ducting"
    if "SPIRAL" in name:
        return "Spiral Ducting"
    if "GRILL" in name or "DIFFUSER" in name:
        return "Grills & Diffusers"
    if "DUCT" in name:
        return "Rectangular / Other Ducting"
    return "Other items"

df["Category"] = df["Particulars"].apply(get_category)


# In[11]:


#renaming the column names for better understaing
df.rename(columns={"Particulars": "Product"}, inplace=True)
df.rename(columns={"Taxable Value": "Selling Price"}, inplace=True)


# In[12]:


df


# In[13]:


df["Category"] = (df["Category"].str.upper().str.strip())


# In[14]:


df= df[[ 'S.No', 'Year', 'Date', 'CompanyName', 'Area', 'Product','Category', 'Quantity',
       'Price per unit', 'Cost', 'Selling Price', 'GST @ 18%',
       'Invoice Value', 'Profit', 'Margin %']]


# In[15]:


df.columns


# In[16]:


df


# # Data understanding & Data analysing

# In[17]:


overall_margin = df["Profit"].sum() / df["Selling Price"].sum() * 100
print("\nOverall profit margin %:", round(overall_margin, 1))


# In[18]:


# Top 10 products by sales
by_product = df.groupby("Product").agg({"Quantity": "sum","Category": "first","Selling Price": "sum","Profit": "sum"})
print("\033[1mTop 10 products by sales:\033[0m")
top10 = by_product.sort_values("Selling Price",ascending=False).head(10).round(0)
top10


# In[19]:


# CUSTOMERS - who matters most 
cust = df.groupby("CompanyName").agg({"Selling Price":"sum"})
print("\033[1mTop 10 customers:\033[0m")
cust10 = cust.sort_values("Selling Price",ascending=False).head(10).round(0)
cust10


# In[20]:


# Lost and new customers (year 1 vs year 2)
table = df.pivot_table(index="CompanyName", columns="Year",values="Selling Price", aggfunc="sum").fillna(0)
year1, year2 = table.columns[0], table.columns[1]
lost = table[(table[year1] > 0) & (table[year2] == 0)]   # bought before, not now
new = table[(table[year1] == 0) & (table[year2] > 0)]    # bought only this year
print(f"\033[1m \nLost customers:\033[0m {len(lost)} (sales lost Rs {lost[year1].sum():,.0f})")
print(f"\033[1mNew customers : \033[0m{len(new)} (sales gained Rs {new[year2].sum():,.0f})")


# In[21]:


# Biggest drop and biggest growth
table["Change"] = table[year2] - table[year1]
print("\033[1m\nBiggest decline:\n\033[0m", table.sort_values("Change").head(5).round(0))
print("\033[1m\nBiggest growth:\n\033[0m", table.sort_values("Change", ascending=False).head(5).round(0))


# In[22]:


print("\033[1mTEST 1: ANOVA\033[0m")
anova_data = df.dropna(subset=["Category", "Selling Price"])
groups = [group["Selling Price"].values
    for _, group in anova_data.groupby("Category")
    if len(group) >= 2
]

if len(groups) >= 2:
    f_stat, p_value = stats.f_oneway(*groups)
    print(f"F-statistic: {f_stat:.4f}")
    print(f"P-value: {p_value:.6f}")
    if p_value < 0.05:
        print("Result: Average selling prices differ across categories.")
    else:
        print("Result: No significant difference detected.")


# In[23]:


print("\033[1m Chart For ANOVA TEST\033[0m")
plt.figure(figsize=(14, 7))
category_order = (df.groupby("Category")["Selling Price"].median().sort_values(ascending=False).index)
sns.boxplot(data=df,x="Category",y="Selling Price",hue="Category",order=category_order,palette="Set2",legend=False,showfliers=False)
plt.title("Category-wise Selling Price Distribution",fontsize=17, fontweight="bold", pad=18)
plt.xlabel("Product Category", fontsize=12)
plt.ylabel("Selling Price (Rs)", fontsize=12)
plt.xticks(rotation=40, ha="right")
plt.tight_layout()
plt.show()


# In[24]:


print("\033[1mTEST 2: CHI-SQUARE TEST\033[0m")
chi_data = df.dropna(subset=["Area", "Category"])
contingency_table = pd.crosstab(chi_data["Area"],chi_data["Category"])
chi2, p_value, dof, expected = stats.chi2_contingency(
    contingency_table
)
print("Contingency table:")
print(contingency_table)
print(f"\nChi-square statistic: {chi2:.4f}")
print(f"Degrees of freedom: {dof}")
print(f"P-value: {p_value:.6f}")
if (expected < 5).any():
    print("Warning: Some expected cell counts are below 5.")
    print("Consider combining rare categories or using an appropriate alternative.")
if p_value < 0.05:
    print("Result: Area and Category are significantly associated.")
else:
    print("Result: No statistically significant association detected.")


# In[25]:


print("\033[1m Chart For CHI-SQUARE TEST\033[0m")
table = pd.crosstab(df["Area"], df["Category"])
plt.figure(figsize=(14, 7))
sns.heatmap(table,cmap="YlOrRd",annot=True if table.size <= 100 else False,fmt="g",linewidths=0.5,linecolor="white",cbar_kws={"label": "Number of Transactions"})
plt.title("Business Area vs Product Category",fontsize=17, fontweight="bold", pad=18)
plt.xlabel("Product Category", fontsize=12)
plt.ylabel("Business Area", fontsize=12)
plt.xticks(rotation=40, ha="right")
plt.tight_layout()
plt.show()


# In[26]:


print("\033[1mTEST 4: SPEARMAN CORRELATION\033[0m")
pairs = [
    ("Quantity", "Selling Price"),
    ("Quantity", "Profit"),
    ("Selling Price", "Profit")
]
for col1, col2 in pairs:
    temp = df[[col1, col2]].dropna()
    corr, p_value = stats.spearmanr(temp[col1], temp[col2])
    print(f"\n{col1} vs {col2}")
    print(f"Spearman correlation: {corr:.4f}")
    print(f"P-value: {p_value:.6f}")
    if p_value < 0.05:
        if corr > 0:
            print("Result: Significant positive association.")
        elif corr < 0:
            print("Result: Significant negative association.")
        else:
            print("Result: No monotonic association detected.")
    else:
        print("Result: No statistically significant association detected.")


# In[27]:


print("\033[1m Chart For SPEARMAN CORRELATION TEST\033[0m")
corr_cols = ["Quantity", "Selling Price", "Profit", "Cost", "Margin %"]
corr = df[corr_cols].corr(method="spearman")
plt.figure(figsize=(10, 7))
sns.heatmap(corr,annot=True,fmt=".2f",cmap="RdYlBu_r",vmin=-1,vmax=1,center=0,linewidths=1,square=True,cbar_kws={"label": "Spearman Correlation"})
plt.title("Spearman Correlation Between Sales Variables",fontsize=17, fontweight="bold", pad=18)
plt.xticks(rotation=30, ha="right")
plt.yticks(rotation=0)
plt.tight_layout()
plt.show()


# In[28]:


pip install sqlalchemy pymysql


# In[29]:


import pandas as pd
from sqlalchemy import create_engine


# In[32]:


engine = create_engine(
    "mysql+pymysql://root:sravan@localhost:3306/data_analysis"
)


# In[34]:


df.to_sql(
    name="sales_data",
    con=engine,
    if_exists="replace",
    index=False
)

print("Data successfully transferred to MySQL!")


# In[35]:


df.to_csv("Manufacturing_Av.csv", index=False)
print("\nDone! Cleaned data and charts are saved.")


# In[ ]:




