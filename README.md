This is a iOS Vendorama search app, like www.vendorama.co.nz

It sends a request to 
https://www.vendorama.co.nz/app/?vq=all

with the search term being vq.

That's it so far, results are a JSON string with 240 results.

GET params:

    vq: the search term
    page: (pagination), e.g. 1 from the 0 to 24th product
    vu: vendor url, e.g. www.tasart.co.nz (or username: tasart)
	vs: related/similar, e.g. 12345.12 ('vendor_id'.'product_id')

    https://www.vendorama.co.nz/app/?vq=all&page=1

results:

	'name'=>'Product Name',
	'price'=>'$1.23',
	'url'=>'https://www.website.co.nz',
	'image'=>"https://www.vendorama.co.nz/i/www.website.co.nz/images/products/00001-1_MD.jpg"

